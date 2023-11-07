#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

set -x #echo on

#pull in cloud-specific variables, e.g. tenancy, namespace
source $LOCAL_PATH/../clouds/oracle.sh

# pull cloud defaults to get ORACLE_REGION
source $LOCAL_PATH/../clouds/all.sh

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -z "$FORCE_BUILD_IMAGE" ] && FORCE_BUILD_IMAGE=false

[ -z "$EXPORT_ENVIRONMENT" ] && EXPORT_ENVIRONMENT="$ENVIRONMENT"

# by default replicate images to the root tenancy
[ -z "$DEST_COMPARTMENT_USE_TENANCY" ] && DEST_COMPARTMENT_USE_TENANCY="true"

if [ -z "$IMAGE_TYPE" ]; then
  echo "No IMAGE_TYPE found. Exiting..."
  exit 10
fi

[ -z "$IMAGE_ARCH" ] && IMAGE_ARCH="x86_64"

case $IMAGE_TYPE in
HotfixJicofo)
  IMAGE_NAME_PREFIX="BuildSignal"
  #if we're not given versions, search for the latest image
  JITSI_MEET_VERSION=$(echo $BASE_SIGNAL_VERSION | cut -d'-' -f2)
  PROSODY_VERSION=$(echo $BASE_SIGNAL_VERSION | cut -d'-' -f3)
  [ -z "$SIGNAL_VERSION" ] && SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
  SERVICE_VERSION="$SIGNAL_VERSION"
  if [ -z "$SERVICE_VERSION" ]; then
    SERVICE_VERSION='latest'
  fi
  ;;

Signal)
  IMAGE_NAME_PREFIX="BuildSignal"

  #if we're not given versions, search for the latest image
  [ -z "$SIGNAL_VERSION" ] && SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
  SERVICE_VERSION="$SIGNAL_VERSION"
  if [ -z "$SERVICE_VERSION" ]; then
    SERVICE_VERSION='latest'
  fi
  ;;

JVB)
  IMAGE_NAME_PREFIX="BuildJVB"

  #if we're not given versions, search for the latest image
  SERVICE_VERSION=$JVB_VERSION
  if [ -z "$SERVICE_VERSION" ]; then
    SERVICE_VERSION='latest'
  else
    [ "$SERVICE_VERSION" == "latest" ] || echo $SERVICE_VERSION | grep -q -- -1$ || SERVICE_VERSION="${SERVICE_VERSION}-1"
  fi
  ;;
Jigasi)
  IMAGE_NAME_PREFIX="BuildJigasi"

  #if we're not given versions, search for the latest image
  SERVICE_VERSION=$JIGASI_VERSION
  if [ -z "$SERVICE_VERSION" ]; then
    SERVICE_VERSION='latest'
  else
    [ "$SERVICE_VERSION" == "latest" ] || echo $SERVICE_VERSION | grep -q -- -1$ || SERVICE_VERSION="${SERVICE_VERSION}-1"
  fi
  ;;
coTURN)
  IMAGE_NAME_PREFIX="BuildCoturn"
  SERVICE_VERSION="latest"
  ;;
JavaJibri)
  IMAGE_NAME_PREFIX="BuildJavaJibri"

  #if we're not given versions, search for the latest image
  SERVICE_VERSION=$JIBRI_VERSION
  if [ -z "$SERVICE_VERSION" ]; then
    SERVICE_VERSION='latest'
  else
    [ "$SERVICE_VERSION" == "latest" ] || echo $SERVICE_VERSION | grep -q -- -1$ || SERVICE_VERSION="${SERVICE_VERSION}-1"
  fi
  ;;
*)
  IMAGE_NAME_PREFIX="Build$IMAGE_TYPE"
  SERVICE_VERSION="latest"
  ;;
esac

[ -z "$EXPORT_ORACLE_REGION" ] && EXPORT_ORACLE_REGION="$ORACLE_REGION"
[ -z "$EXPORT_ORACLE_REGION" ] && EXPORT_ORACLE_REGION=$DEFAULT_ORACLE_REGION

ORACLE_CLOUD_NAME="$EXPORT_ORACLE_REGION-$EXPORT_ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ "$DEST_COMPARTMENT_USE_TENANCY" == "true" ] && DEST_COMPARTMENT_OCID="$TENANCY_OCID"

[ -z "$DEST_COMPARTMENT_OCID" ] && DEST_COMPARTMENT_OCID="$COMPARTMENT_OCID"

# Identify the replication DESTINATION regions
##############################################

 [ -z "$IMAGE_REGIONS" ] && IMAGE_REGIONS="$ORACLE_IMAGE_REGIONS"

DESTINATION_ORACLE_REGIONS=()
for REGION in $IMAGE_REGIONS; do
  if [[ "$REGION" == "$EXPORT_ORACLE_REGION" ]]; then
    echo "Skipping export to local region $REGION"
  else
    DESTINATION_ORACLE_REGIONS+=($REGION)
  fi
done

if ((${#DESTINATION_ORACLE_REGIONS[@]})); then
  echo Import $IMAGE_TYPE image in this Oracle regions: "${DESTINATION_ORACLE_REGIONS[@]}" if there is no other $IMAGE_TYPE image with version $SERVICE_VERSION
else
  echo "No DESTINATION_ORACLE_REGIONS found. Exiting..."
  exit 1
fi

###Check if a image with this version already exists in the destination regions
IMPORT_ORACLE_REGIONS=()
for REGION in "${DESTINATION_ORACLE_REGIONS[@]}"; do
  if $FORCE_BUILD_IMAGE; then
    IMPORT_ORACLE_REGIONS+=($REGION)
  else
    IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type $IMAGE_TYPE --version "$SERVICE_VERSION" --architecture "$IMAGE_ARCH" --region="$REGION" --compartment_id="$DEST_COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

    if [ $? -eq 0 ]; then
      echo "A $IMAGE_TYPE image with version $SERVICE_VERSION already exists in $REGION"
    else
      echo "No $IMAGE_TYPE image with version $SERVICE_VERSION was found in $REGION. Will import one.."
      IMPORT_ORACLE_REGIONS+=($REGION)
    fi
  fi
done

if ((${#IMPORT_ORACLE_REGIONS[@]} == 0)); then
  echo "A $IMAGE_TYPE image with version $SERVICE_VERSION already exists in all the regions. Exiting.."
  exit 0
fi

# Identify the SOURCE image details; EXPORT to Object Storage if the image is not already there
###############################################################################################

###Find details about the existing image
IMAGE_DETAILS=$($LOCAL_PATH/oracle_custom_images.py --type $IMAGE_TYPE --version "$SERVICE_VERSION" --architecture "$IMAGE_ARCH" --region "$EXPORT_ORACLE_REGION" --compartment_id "$COMPARTMENT_OCID" --tag_namespace "$TAG_NAMESPACE" --image_details true)
if [ -z "$IMAGE_DETAILS" ]; then
  echo "No IMAGE_DETAILS found.  Exiting..."
  exit 2
fi

IMAGE_OCID=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_id'\")
IMAGE_TIMESTAMP=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_epoch_ts'\")
IMAGE_TYPE=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_type'\")
IMAGE_VERSION=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_version'\")
IMAGE_BUILD=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_build'\")
IMAGE_BASE_TYPE=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_base_type'\")
IMAGE_ARCHITECTURE=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_architecture'\")
IMAGE_BASE_OCID=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_base_ocid'\")
IMAGE_ENVIRONMENT_TYPE=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_environment_type'\")
IMAGE_META_VERSION=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_meta_version'\")
IMAGE_COMPARTMENT=$(echo "$IMAGE_DETAILS" | jq -r .\"'image_compartment_id'\")

[ -z "$IMAGE_ARCHITECTURE" ] && IMAGE_ARCHITECTURE="x86_64"

if [ "$IMAGE_TYPE" == "JVB" ] || [ "$IMAGE_TYPE" == "JavaJibri" ] || [ "$IMAGE_TYPE" == "Jigasi" ]; then
  IMAGE_NAME="$IMAGE_NAME_PREFIX-$EXPORT_ORACLE_REGION-$EXPORT_ENVIRONMENT-$SERVICE_VERSION-$IMAGE_TIMESTAMP"
else
  IMAGE_NAME="$IMAGE_NAME_PREFIX-$EXPORT_ORACLE_REGION-$EXPORT_ENVIRONMENT-$IMAGE_TIMESTAMP"
fi

PREAUTH_URI_NAME="$IMAGE_NAME-preauth-uri"

###Calculate expire timestamp for pre-authenticated request on different platforms
case $(uname) in
Darwin)
  TIME_EXPIRES=$(date -v +2d +%Y-%m-%d)
  ;;
Linux)
  TIME_EXPIRES=$(date -u --date="+2 day" +%Y-%m-%d)
  ;;
*)
  echo "Platform not supported. Exiting.."
  exit 9
  ;;
esac

BUCKET_NAME="images-$EXPORT_ENVIRONMENT"

###Export image to an Object Storage Bucket, if there is no other image already exported
LIST_IMAGE_JSON=$(oci os object list --bucket-name "$BUCKET_NAME" --region="$EXPORT_ORACLE_REGION" --prefix "$IMAGE_NAME")
COUNT_IMAGE=$(echo "$LIST_IMAGE_JSON" | jq -r .data | jq '. | length')

if [ "$COUNT_IMAGE" -gt 0 ]; then
  if $FORCE_BUILD_IMAGE; then
    echo "A $IMAGE_TYPE image with the prefix $IMAGE_NAME was found in Object Storage. Exporting anyway due to FORCE_BUILD_IMAGE=true"
    EXPORT_IMAGE=true
  else
    echo "A $IMAGE_TYPE image with the prefix $IMAGE_NAME was found in Object Storage. Do not export it twice"
    EXPORT_IMAGE=false
  fi
else
  EXPORT_IMAGE=true
fi

INITIAL_SLEEP=600
SLEEP_INTERVAL=60
SLEEP_MAX=3600

if ($EXPORT_IMAGE); then
  EXPORT_IMAGE_STATE_JSON=$(oci compute image export to-object --image-id "$IMAGE_OCID" --namespace "$NAMESPACE" --bucket-name "$BUCKET_NAME" --region="$EXPORT_ORACLE_REGION" --name "$IMAGE_NAME")

  LIFECYCLE_STATE=$(echo "$EXPORT_IMAGE_STATE_JSON" | jq -r .data.\"lifecycle-state\")
  WORK_REQUEST_ID=$(echo "$EXPORT_IMAGE_STATE_JSON" | jq -r .\"opc-work-request-id\")

  if [ "$LIFECYCLE_STATE" == "EXPORTING" ]; then
    echo "Exporting image from region $EXPORT_ORACLE_REGION"
    sleep $INITIAL_SLEEP
    ST=0

    WORK_REQUEST_JSON=$(oci work-requests work-request get --work-request-id "$WORK_REQUEST_ID" --region "$EXPORT_ORACLE_REGION")
    WORK_REQUEST_STATUS=$(echo "$WORK_REQUEST_JSON" | jq -r .data.status)

    while [ "$WORK_REQUEST_STATUS" == 'IN_PROGRESS' ]; do
      echo "Exporting in progress.."
      sleep $SLEEP_INTERVAL
      ST=$((ST + SLEEP_INTERVAL))

      WORK_REQUEST_JSON=$(oci work-requests work-request get --work-request-id "$WORK_REQUEST_ID" --region "$EXPORT_ORACLE_REGION")
      WORK_REQUEST_STATUS=$(echo "$WORK_REQUEST_JSON" | jq -r .data.status)

      if [[ $ST -ge $SLEEP_MAX ]]; then
        echo "Exporting takes too long. Exiting.."
        exit 3
      fi
    done

    echo "The image was exported. Status is $WORK_REQUEST_STATUS"

    if [ "$WORK_REQUEST_STATUS" != "SUCCEEDED" ]; then
      echo "Work request failed. Work request id is $WORK_REQUEST_ID"
      exit 4
    fi
  else
    echo "Could not export image. Lifecycle state is $LIFECYCLE_STATE"
    exit 5
  fi
fi

# IMPORT from Object Storage into the replication DESTINATION regions
########################################################################

####Create pre-authenticated request
PREAUTH_URI_JSON=$(oci os preauth-request create --namespace "$NAMESPACE" --region "$EXPORT_ORACLE_REGION" --access-type ObjectRead --bucket-name "$BUCKET_NAME" --name "$PREAUTH_URI_NAME" --time-expires "$TIME_EXPIRES" -on "$IMAGE_NAME")
ACCESS_URI=$(echo "$PREAUTH_URI_JSON" | jq -r .data.\"access-uri\")

if [ -z "$ACCESS_URI" ]; then
  echo "Error creating pre-authenticated request. No ACCESS_URI found. Exiting.."
  exit 8
fi

OBJECT_STORAGE_URL="https://objectstorage.$EXPORT_ORACLE_REGION.oraclecloud.com$ACCESS_URI"

###Import image in all the regions using the Object Storage url
WORK_REQUEST_IDS=()
for REGION in "${IMPORT_ORACLE_REGIONS[@]}"; do

  if [[ "$REGION" == "$EXPORT_ORACLE_REGION" ]]; then
    # only export this region if compartments differ
    if [[ "$IMAGE_COMPARTMENT" == "$DEST_COMPARTMENT_OCID" ]]; then
      echo "Skipping local region $REGION, since image already exists in destination compartment $IMAGE_COMPARTMENT and region"
      continue;
    fi
  fi
  if [ "$IMAGE_TYPE" == "JVB" ] || [ "$IMAGE_TYPE" == "JavaJibri" ] || [ "$IMAGE_TYPE" == "Jigasi" ] || [ "$IMAGE_TYPE" == "Signal" ]; then
    if [ "$DEST_COMPARTMENT_USE_TENANCY" == "true" ]; then
      IMAGE_NAME="$IMAGE_NAME_PREFIX-$REGION-$SERVICE_VERSION-$IMAGE_TIMESTAMP"
    else
      IMAGE_NAME="$IMAGE_NAME_PREFIX-$REGION-$ENVIRONMENT-$SERVICE_VERSION-$IMAGE_TIMESTAMP"
    fi
    DEFINED_TAGS='{
      "'${TAG_NAMESPACE}'": {
      "Name": "'${IMAGE_NAME}'",
      "build_id": "'${IMAGE_BUILD}'",
      "Version": "'${IMAGE_VERSION}'",
      "TS": "'${IMAGE_TIMESTAMP}'",
      "MetaVersion": "'${IMAGE_META_VERSION}'",
      "Type": "'${IMAGE_TYPE}'",
      "environment_type": "'${IMAGE_ENVIRONMENT_TYPE}'"
      },
      "jitsi": {
      "Name": "'${IMAGE_NAME}'",
      "build_id": "'${IMAGE_BUILD}'",
      "Version": "'${IMAGE_VERSION}'",
      "Arch": "'${IMAGE_ARCHITECTURE}'",
      "BaseImageType": "'${IMAGE_BASE_TYPE}'",
      "BaseImageOCID": "'${IMAGE_BASE_OCID}'",
      "TS": "'${IMAGE_TIMESTAMP}'",
      "MetaVersion": "'${IMAGE_META_VERSION}'",
      "Type": "'${IMAGE_TYPE}'",
      "environment_type": "'${IMAGE_ENVIRONMENT_TYPE}'"
      }      
    }'
  else
    if [ "$DEST_COMPARTMENT_USE_TENANCY" == "true" ]; then
      IMAGE_NAME="$IMAGE_NAME_PREFIX-$REGION-$IMAGE_TIMESTAMP"
    else
      IMAGE_NAME="$IMAGE_NAME_PREFIX-$REGION-$ENVIRONMENT-$IMAGE_TIMESTAMP"
    fi

    DEFINED_TAGS='{
      "'${TAG_NAMESPACE}'": {
      "Name": "'${IMAGE_NAME}'",
      "build_id": "'${IMAGE_BUILD}'",
      "TS": "'${IMAGE_TIMESTAMP}'",
      "Type": "'${IMAGE_TYPE}'",
      "environment_type": "'${IMAGE_ENVIRONMENT_TYPE}'"
      },
      "jitsi": {
      "Name": "'${IMAGE_NAME}'",
      "build_id": "'${IMAGE_BUILD}'",
      "Arch": "'${IMAGE_ARCHITECTURE}'",
      "BaseImageType": "'${IMAGE_BASE_TYPE}'",
      "BaseImageOCID": "'${IMAGE_BASE_OCID}'",
      "TS": "'${IMAGE_TIMESTAMP}'",
      "Type": "'${IMAGE_TYPE}'",
      "environment_type": "'${IMAGE_ENVIRONMENT_TYPE}'"
      }      
    }'
  fi

  IMPORT_IMAGE_STATE_JSON=$(oci compute image import from-object-uri --compartment-id "$DEST_COMPARTMENT_OCID" --region "$REGION" --uri "$OBJECT_STORAGE_URL" --display-name "$IMAGE_NAME" --defined-tags "$DEFINED_TAGS")

  WORK_REQUEST_ID=$(echo "$IMPORT_IMAGE_STATE_JSON" | jq -r .\"opc-work-request-id\")
  WORK_REQUEST_IDS+=($WORK_REQUEST_ID)

  NEW_OCID=$(echo "$IMPORT_IMAGE_STATE_JSON" | jq -r .data.\"id\")
  echo "Importing image $IMAGE_NAME in region $REGION with OCID $NEW_OCID, updating shape compatibility"
  $LOCAL_PATH/oracle_custom_images.py --add_shape_compatibility --image_id $NEW_OCID --region $REGION

done

sleep $INITIAL_SLEEP
ST=0

i=0
for WORK_REQUEST_ID in "${WORK_REQUEST_IDS[@]}"; do

  if [[ "$REGION" == "$EXPORT_ORACLE_REGION" ]]; then
    # only export this region if compartments differ
    if [[ "$IMAGE_COMPARTMENT" == "$DEST_COMPARTMENT_OCID" ]]; then
      echo "Skipping check of local region $REGION, since image already exists in destination compartment $IMAGE_COMPARTMENT and region"
      continue;
    fi
  fi

  REGION="${IMPORT_ORACLE_REGIONS[i]}"
  i=$((i + 1))

  WORK_REQUEST_JSON=$(oci work-requests work-request get --work-request-id "$WORK_REQUEST_ID" --region "$REGION")
  WORK_REQUEST_STATUS=$(echo "$WORK_REQUEST_JSON" | jq -r .data.status)
  echo "Processing work request id $WORK_REQUEST_ID"

  while [ "$WORK_REQUEST_STATUS" == 'IN_PROGRESS' ]; do
    echo "Importing in progress.."
    sleep $SLEEP_INTERVAL
    ST=$((ST + SLEEP_INTERVAL))

    WORK_REQUEST_JSON=$(oci work-requests work-request get --work-request-id "$WORK_REQUEST_ID" --region "$REGION")
    WORK_REQUEST_STATUS=$(echo "$WORK_REQUEST_JSON" | jq -r .data.status)

    if [[ $ST -ge $SLEEP_MAX ]]; then
      echo "Importing takes too long. Exiting.."
      exit 6
    fi
  done

  echo "Work request finished. Status is $WORK_REQUEST_STATUS"

  if [ "$WORK_REQUEST_STATUS" != "SUCCEEDED" ]; then
    echo "Work request failed. Work request id is $WORK_REQUEST_ID"
    exit 7
  fi

done
