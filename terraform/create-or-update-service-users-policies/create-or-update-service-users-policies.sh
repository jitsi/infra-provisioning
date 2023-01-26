#!/bin/bash
set -x #echo on

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../../clouds/all.sh ] && . $LOCAL_PATH/../../clouds/all.sh

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$SERVICE_USER_TYPE" ]; then
  echo "No SERVICE_USER_TYPE found.  Exiting..."
  exit 1
fi

###Find equivalent Oracle regions
REGIONS=()
for CLOUD_NAME in $RELEASE_CLOUDS; do
  source $LOCAL_PATH/../../clouds/$CLOUD_NAME.sh
  if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION equivalent found for cloud ${CLOUD_NAME}, exiting..."
    exit 2
  fi
  REGIONS+=($ORACLE_REGION)
  unset ORACLE_REGION
done


#Consider eu-amsterdam-1 the home region to save the terraform state for policies
ORACLE_REGION=eu-amsterdam-1
ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/"${ORACLE_CLOUD_NAME}".sh

COMPARTMENT_NAME="$ENVIRONMENT"
VIDEO_EDITOR_GROUP_NAME="$SERVICE_USER_TYPE-video-editor-group"
VIDEO_EDITOR_POLICY_NAME="$COMPARTMENT_NAME-$SERVICE_USER_TYPE-video-editor-policy"
CS_HISTORY_GROUP_NAME="$SERVICE_USER_TYPE-content-sharing-history-group"
CS_HISTORY_POLICY_NAME="$COMPARTMENT_NAME-$SERVICE_USER_TYPE-content-sharing-history-policy"

# convert array to serialized list;
# this way you can use bash array as terraform list of string variable
REGIONS_WITH_QUOTES=()
for ENTRY in "${REGIONS[@]}"; do
  REGIONS_WITH_QUOTES+=("\"${ENTRY}\"")
done
REGION_LIST=$(
  IFS=,
  echo ["${REGIONS_WITH_QUOTES[*]}"]
)

if [ -z "$REGION_LIST" ] || [ "$REGION_LIST" == '[]' ]; then
  echo "Empty REGION_LIST. Exiting.."
  exit 3
fi

if [ -z "$CS_HISTORY_ORACLE_REGIONS" ]; then
  echo "Empty CS_HISTORY_ORACLE_REGIONS. Exiting..."
  exit 4
fi

CS_HISTORY_REGIONS_WITH_QUOTES=()
for ENTRY in $CS_HISTORY_ORACLE_REGIONS; do
  CS_HISTORY_REGIONS_WITH_QUOTES+=("\"${ENTRY}\"")
done
CS_HISTORY_REGION_LIST=$(
  IFS=,
  echo ["${CS_HISTORY_REGIONS_WITH_QUOTES[*]}"]
)

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/$SERVICE_USER_TYPE-service-users-policies/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

#The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure $TF_POST_PARAMS

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_name=$COMPARTMENT_NAME" \
  -var="compartment_id=$COMPARTMENT_OCID" \
  -var="regions=$REGION_LIST" \
  -var="video_editor_group_name=$VIDEO_EDITOR_GROUP_NAME" \
  -var="video_editor_policy_name=$VIDEO_EDITOR_POLICY_NAME" \
  -var="cs_history_regions=$CS_HISTORY_REGION_LIST" \
  -var="cs_history_group_name=$CS_HISTORY_GROUP_NAME" \
  -var="cs_history_policy_name=$CS_HISTORY_POLICY_NAME" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
  