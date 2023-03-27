#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

[ -z "$JIBRI_TYPE" ] && export JIBRI_TYPE="java-jibri"
if [ "$JIBRI_TYPE" != "java-jibri" ] &&  [ "$JIBRI_TYPE" != "sip-jibri" ]; then
  echo "Unsupported jibri type $JIBRI_TYPE";
  exit 206
fi

[ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION"
[ -z "$NAME_ROOT" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
[ -z "$NAME" ] && NAME="$NAME_ROOT-$JIBRI_TYPE"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/jibris/$NAME/terraform.tfstate"

echo "Get Jibri resources before destroying them and make sure we clean up all"
. ../all/bin/terraform/jibri-state/jibri-state.sh

INSTANCE_POOL_DETAILS=$(oci compute-management instance-pool get --instance-pool-id "$JIBRI_STATE_INSTANCE_POOL_ID" --region $ORACLE_REGION)
INSTANCE_CONFIGURATION_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.data."instance-configuration-id"')

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
  -force-copy $TF_POST_PARAMS

terraform $TF_GLOBALS_CHDIR destroy \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -auto-approve $TF_POST_PARAMS

if [ $? -eq 0 ]; then
  echo "Terraform succeeded, exiting cleanly"
  if [ "$JIBRI_STATE_INSTANCE_CONFIGURATION_ID" != "$INSTANCE_CONFIGURATION_ID" ]; then
    echo "Clean up instance configuration associated with the previous destroyed instance pool"
    oci compute-management instance-configuration delete --instance-configuration-id "$INSTANCE_CONFIGURATION_ID" --region $ORACLE_REGION --force
  fi
  exit 0
else
  echo "Terraform failed to delete cleanly, instrumenting existing instances"
  # list existing instances in shard
  terraform $TF_GLOBALS_CHDIR show -json | jq -r ".values.root_module.resources|map(select(.type ==\"oci_core_instance_pool\"))|.[]|.values.id,.values.compartment_id" | while
    read POOL_ID
    read COMPARTMENT_ID
  do
    INSTANCES=$(oci --region "$ORACLE_REGION" compute-management instance-pool list-instances --instance-pool-id "$POOL_ID" --compartment-id "$COMPARTMENT_ID" | jq -r ".data[].id")
    # run oci compute instance terminate --force --instance-id <ID> on each
    for ID in $INSTANCES; do
      echo "TERMINATING $ID"
      oci --region "$ORACLE_REGION" compute instance terminate --force --instance-id $ID
    done
  done
  # sleep requisite time
  sleep 1200
  # re-run terraform destroy command
  terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS
  if [[ $? == 0 ]]; then
    if [ "$JIBRI_STATE_INSTANCE_CONFIGURATION_ID" != "$INSTANCE_CONFIGURATION_ID" ]; then
      echo "Clean up instance configuration associated with the previous destroyed instance pool"
      oci compute-management instance-configuration delete --instance-configuration-id "$INSTANCE_CONFIGURATION_ID" --region $ORACLE_REGION --force
    fi
  fi
  exit $?
fi
