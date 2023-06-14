#!/bin/bash
set -x #echo on


SCRIPT_LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# We need an envirnment "all"
if [ -z $ENVIRONMENT ]; then
  echo "No Environment provided or found.  Exiting without creating stack."
  exit 202
fi

# Get the list of Public IP from the existing Coturn Instance Pool
if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi

[ -z "$COTURN_INSTANCE_POOL_NAME" ] && COTURN_INSTANCE_POOL_NAME="$ENVIRONMENT-$ORACLE_REGION-coturn"
[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/coturns/$COTURN_INSTANCE_POOL_NAME/terraform.tfstate"

CURRENT_PATH=$(pwd)


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$SCRIPT_LOCAL_PATH"
  TF_POST_PARAMS=
else
  cd $SCRIPT_LOCAL_PATH
  TF_POST_PARAMS="$SCRIPT_LOCAL_PATH"
fi

# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure

INSTANCE_POOL_RESOURCE=$(terraform $TF_GLOBALS_CHDIR state list | grep "oci_core_instance_pool.oci")

INSTANCE_POOL_LINE=$(terraform $TF_GLOBALS_CHDIR state show "$INSTANCE_POOL_RESOURCE" | grep "instancepool")
INSTANCE_POOL_ID_START=${INSTANCE_POOL_LINE#*id*=*\"} # delete shortest match of pattern from the beginning
COTURN_STATE_INSTANCE_POOL_ID=${INSTANCE_POOL_ID_START%%\"*} # delete longest match of pattern from the end
export COTURN_STATE_INSTANCE_POOL_ID

COMPARTMENT_ID_LINE=$(terraform $TF_GLOBALS_CHDIR state show "$INSTANCE_POOL_RESOURCE" | grep "compartment_id")
COMPARTMENT_ID_START=${COMPARTMENT_ID_LINE#*compartment_id*=*\"} # delete shortest match of pattern from the beginning
COTURN_STATE_COMPARTMENT_ID=${COMPARTMENT_ID_START%%\"*} # delete longest match of pattern from the end
export COTURN_STATE_COMPARTMENT_ID


if [[ "$TERRAFORM_MAJOR_VERSION" == "v0" ]]; then
  cd $CURRENT_PATH
fi