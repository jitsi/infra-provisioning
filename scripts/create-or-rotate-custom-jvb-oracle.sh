#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# We need an environment
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

# e.g. terraform/wavefront-proxy
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

CLOUD_PROVIDER="oracle"

# We need an environment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

if [ -z "$CLOUD_NAME" ]; then
  echo "No aws CLOUD_NAME found.  Exiting..."
  exit 204
fi

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER="0"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

#if we're not given versions, search for the latest of each type of image
[ -z "$JVB_VERSION" ] && JVB_VERSION='latest'

[ -z "$SKIP_SCALE_DOWN" ] && SKIP_SCALE_DOWN="false"

# first check E4 flag
if [ "$ENABLE_E_4" == "true" ]; then
  JVB_SHAPE="$SHAPE_E_4"
fi

# next check E5 flag
if [ "$ENABLE_E_5" == "true" ]; then
  JVB_SHAPE="$SHAPE_E_5"
fi

# use A1 if configured
if [ "$ENABLE_A_1" == "true" ]; then
  JVB_SHAPE="$SHAPE_A_1"
fi

# use A2 if configured
if [ "$ENABLE_A_2" == "true" ]; then
  if [[ "$JVB_A2_AVAILABLE" == "true" ]]; then
    JVB_SHAPE="$SHAPE_A_2"
  fi
fi

[ -z "$SHAPE" ] && SHAPE="$JVB_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$DEFAULT_SHAPE"

arch_from_shape $SHAPE


JVB_NOMAD_VARIABLE="jvb_enable_nomad"

[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

NOMAD_JVB_FLAG="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
  NOMAD_JVB_FLAG="$(cat $CONFIG_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
fi
if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
  NOMAD_JVB_FLAG=
fi

[ -z "$NOMAD_JVB_FLAG" ] && NOMAD_JVB_FLAG="false"

JVB_IMAGE_TYPE="JVB"

if [[ "$NOMAD_JVB_FLAG" == "true" ]]; then
  JVB_IMAGE_TYPE="JammyBase"
  JVB_VERSION="latest"
  AUTOSCALER_TYPE="nomad"
  [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="NomadJVBCustomGroup"
  echo "Using Nomad AUTOSCALER_URL"
  AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME"
  [ -z $JVB_MAX_COUNT ] && JVB_MAX_COUNT=2
  [ -z $JVB_MIN_COUNT ] && JVB_MIN_COUNT=1
  [ -z $JVB_DOWNSCALE_COUNT ] && JVB_DOWNSCALE_COUNT="0.4"
  [ -z $JVB_SCALING_INCREASE_RATE ] && JVB_SCALING_INCREASE_RATE=1
  [ -z $JVB_SCALING_DECREASE_RATE ] && JVB_SCALING_DECREASE_RATE=1
  [ -z "$JVB_SCALE_UP_PERIODS_COUNT" ] && JVB_SCALE_UP_PERIODS_COUNT=2
  [ -z "$JVB_SCALE_DOWN_PERIODS_COUNT" ] && JVB_SCALE_DOWN_PERIODS_COUNT=20
  [ -z "$JVB_AVAILABLE_COUNT" ] && JVB_AVAILABLE_COUNT="0.65"

fi

#Look up images based on version, or default to latest
[ -z "$JVB_IMAGE_OCID" ] && JVB_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type $JVB_IMAGE_TYPE --version "$JVB_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

#No image was found, probably not built yet?
if [ -z "$JVB_IMAGE_OCID" ]; then
  echo "No JVB_IMAGE_OCID provided or found. Exiting.. "
  exit 210
fi

if [ -z "$JVB_RELEASE_NUMBER" ]; then
  echo "No JVB_RELEASE_NUMBER found.  Exiting..."
  exit 206
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="$RELEASE_BRANCH"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

if [ -z "$SHARD" ]; then
  echo "Error. SHARD is empty"
  exit 213
fi

[ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="JVBCustomGroup"
[ -z "$GROUP_NAME" ] && GROUP_NAME=${SHARD}-"$NAME_ROOT_SUFFIX"
[ -z "$TS" ] && TS=$(date +%s)
[ -z "$INSTANCE_CONFIG_NAME" ] && export INSTANCE_CONFIG_NAME="${SHARD}-JVBInstanceConfig-${TS}"

[ -z "$JVB_PROTECTED_TTL_SEC" ] && JVB_PROTECTED_TTL_SEC=900
METADATA_PATH="$LOCAL_PATH/../terraform/create-jvb-instance-configuration/user-data/postinstall-runner-oracle.sh"
METADATA_LIB_PATH="$LOCAL_PATH/../terraform/lib"
[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub

if [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
fi

if [[ "$SHAPE" == "VM.Standard.E5.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
fi

if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=8
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
fi

if [[ "$SHAPE" == "VM.Standard.A2.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
fi

if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
fi

echo "Retrieve instance group details for group $GROUP_NAME"
instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group named $GROUP_NAME was found. Will create one"
  export SKIP_AWS_SCALE_DOWN=true
  $LOCAL_PATH/create-shard-custom-jvbs-oracle.sh

elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  EXISTING_INSTANCE_CONFIGURATION_ID=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.instanceConfigurationId")
  EXISTING_MAXIMUM=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.maxDesired")
  if [ -z "$EXISTING_INSTANCE_CONFIGURATION_ID" ] || [ "$EXISTING_INSTANCE_CONFIGURATION_ID" == "null" ]; then
    echo "No Instance Configuration was found on the group details $GROUP_NAME. Exiting.."
    exit 206
  fi

  [ -z "$PROTECTED_INSTANCES_COUNT" ] && PROTECTED_INSTANCES_COUNT=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.desiredCount")
  if [ -z "$PROTECTED_INSTANCES_COUNT" ]; then
    echo "Something went wrong, could not extract PROTECTED_INSTANCES_COUNT from instanceGroup.scalingOptions.desiredCount";
    exit 208
  fi

  NEW_MAXIMUM_DESIRED=$((EXISTING_MAXIMUM + PROTECTED_INSTANCES_COUNT))

  if [[ "$SKIP_SCALE_DOWN" == "true" ]]; then
    echo "Skipping scale down step, setting NEW_MAXIMUM_DESIRED to EXISTING_MAXIMUM"
    NEW_MAXIMUM_DESIRED=$EXISTING_MAXIMUM
    PROTECTED_INSTANCES_COUNT=0
  fi

  if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
    echo "Creating new Instance Configuration for group $GROUP_NAME based on the existing one"
    SHAPE_PARAMS=""
    [ ! -z "$SHAPE" ] && SHAPE_PARAMS="$SHAPE_PARAMS --shape $SHAPE"
    [ ! -z "$OCPUS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --ocpus $OCPUS"
    [ ! -z "$MEMORY_IN_GBS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --memory $MEMORY_IN_GBS"

    NEW_INSTANCE_CONFIGURATION_ID=$($LOCAL_PATH/rotate_instance_configuration_oracle.py --region "$ORACLE_REGION" --display_name "$INSTANCE_CONFIG_NAME" --image_id "$JVB_IMAGE_OCID" \
      --jvb_release_number "$JVB_RELEASE_NUMBER"  --release_number "$RELEASE_NUMBER" --git_branch "$ORACLE_GIT_BRANCH" \
      --infra_customizations_repo "$INFRA_CUSTOMIZATIONS_REPO" --infra_configuration_repo "$INFRA_CONFIGURATION_REPO" \
      --instance_configuration_id "$EXISTING_INSTANCE_CONFIGURATION_ID" --tag_namespace "$TAG_NAMESPACE" --user_public_key_path "$USER_PUBLIC_KEY_PATH" --metadata_eip --metadata_lib_path "$METADATA_LIB_PATH" --metadata_path "$METADATA_PATH" --custom_autoscaler \
      --metadata_extras="export NOMAD_FLAG=$NOMAD_JVB_FLAG" \
      $SHAPE_PARAMS)

    if [ -z "$NEW_INSTANCE_CONFIGURATION_ID" ] || [ "$NEW_INSTANCE_CONFIGURATION_ID" == "null" ]; then
      echo "No Instance Configuration was created for group $GROUP_NAME. Exiting.."
      exit 207
    fi
    echo "Old Instance Configuration id is $EXISTING_INSTANCE_CONFIGURATION_ID;
          New Instance Configuration id is $NEW_INSTANCE_CONFIGURATION_ID"

    if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
      echo "Tagging JVB image as production"
      $LOCAL_PATH/oracle_custom_images.py --tag_production --image_id $JVB_IMAGE_OCID --region $ORACLE_REGION
    fi
  fi
  if [[ "$CLOUD_PROVIDER" == "nomad" ]]; then
    # re-deploy nomad job definition for pool
    $LOCAL_PATH/deploy-nomad-jvb.sh

    if [ $? -gt 0 ]; then
        echo "Failed to deploy nomad job, exiting..."
        exit 222
    fi

    # re-use existing configuration id
    echo "Re-using existing Instance Configuration for nomad group $GROUP_NAME"
    NEW_INSTANCE_CONFIGURATION_ID="$EXISTING_INSTANCE_CONFIGURATION_ID"
    export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
  fi

  echo "Will launch $PROTECTED_INSTANCES_COUNT protected instances (new max $NEW_MAXIMUM_DESIRED) in group $GROUP_NAME"
  instanceGroupLaunchResponse=$(curl -s -w "\n %{http_code}" -X POST \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/actions/launch-protected \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
  "instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",
  "count": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '$NEW_MAXIMUM_DESIRED',
  "protectedTTLSec": '$JVB_PROTECTED_TTL_SEC'
}')
  launchGroupHttpCode=$(tail -n1 <<<"$instanceGroupLaunchResponse" | sed 's/[^0-9]*//g')
  if [ "$launchGroupHttpCode" == 200 ]; then
    echo "Successfully launched $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"

# TODO: clean up not old instance configuration, but all except current and previous
#    echo "Will delete the old Instance Configuration for group $GROUP_NAME"
#    oci compute-management instance-configuration delete --instance-configuration-id "$EXISTING_INSTANCE_CONFIGURATION_ID" --region "$ORACLE_REGION" --force
  else
    echo "Error launching $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $launchGroupHttpCode"
    exit 208
  fi

# check flag for skipping scale down step
  if [[ "$SKIP_SCALE_DOWN" != "true" ]]; then
    #Wait as much as it will take to provision the new instances, before scaling down the existing ones
    sleep 480

    echo "Will scale down the group $GROUP_NAME and keep only the $PROTECTED_INSTANCES_COUNT protected instances with maximum $EXISTING_MAXIMUM"
    instanceGroupScaleDownResponse=$(curl -s -w "\n %{http_code}" -X PUT \
      "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/desired \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d '{
    "desiredCount": '"$PROTECTED_INSTANCES_COUNT"',
    "maxDesired": '"$EXISTING_MAXIMUM"'
  }')
    scaleDownGroupHttpCode=$(tail -n1 <<<"$instanceGroupScaleDownResponse" | sed 's/[^0-9]*//g')
    if [ "$scaleDownGroupHttpCode" == 200 ]; then
      echo "Successfully scaled down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"
    else
      echo "Error scaling down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $scaleDownGroupHttpCode"
      exit 209
    fi
  else
    echo "Skipping scale down step as SKIP_SCALE_DOWN=true, exiting..."
    exit 0
  fi
else
  echo "No group named $GROUP_NAME was found nor created. AutoScaler response status code is $getGroupHttpCode"
  exit 210
fi
