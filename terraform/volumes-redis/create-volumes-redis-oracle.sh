#!/bin/bash

set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"

S3_STATE_BASE="$ENVIRONMENT/volumes-redis"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_CLI_ARGS=""
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
  -var="oracle_region=$ORACLE_REGION"\
  -var="tenancy_ocid=$TENANCY_OCID"\
  -var="compartment_ocid=$COMPARTMENT_OCID"\
  -var="environment=$ENVIRONMENT"\
  $ACTION_POST_PARAMS $TF_POST_PARAMS
