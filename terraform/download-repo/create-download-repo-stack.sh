#!/bin/bash
set -x #echo on

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

# pull in stack-env.sh from sites/$ENVIRONMENT
. sites/$ENVIRONMENT/stack-env.sh

# e.g. terraform/wavefront-proxy
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="haproxy"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"
[ -z "$HAPROXY_RELEASE_NUMBER" ] && HAPROXY_RELEASE_NUMBER="0"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

[ -z "$ORACLE_HOME_REGION" ] && ORACLE_HOME_REGION="eu-frankfurt-1"
[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_IDENTITY_ENDPOINT" ] && S3_IDENTITY_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_HOME_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/download-repo/terraform.tfstate"
[ -z "$S3_IDENTITY_STATE_KEY" ] && S3_IDENTITY_STATE_KEY="$ENVIRONMENT/download-repo/identity.tfstate"


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_GLOBALS_CHDIR_ID="-chdir=$LOCAL_PATH/identity-policy"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
  TF_POST_PARAMS_ID="$LOCAL_PATH/identity-policy"
fi


# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR_ID init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_IDENTITY_STATE_KEY" \
  -backend-config="region=$ORACLE_HOME_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_IDENTITY_ENDPOINT" \
  -reconfigure $TF_POST_PARAMS_ID

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR_ID $ACTION \
  -var="oracle_region=$ORACLE_HOME_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS_ID


# init the terraform
# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
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
  -var="environment=$ENVIRONMENT" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="bucket_namespace=$ORACLE_S3_NAMESPACE" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
