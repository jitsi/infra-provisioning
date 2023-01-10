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

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$SHARD" ]; then
  echo "No SHARD found.  Exiting..."
  exit 1
fi

if [ -z "$ORACLE_REGION" ]; then
  # Extract EC2_REGION from the shard name and use it to get the ORACLE_REGION
  ORACLE_REGION=$($LOCAL_PATH/../../scripts/shard.py --shard_region --environment=$ENVIRONMENT --shard=$SHARD)
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi


export SHARD
export ANSIBLE_SSH_USER
export ORACLE_REGION

# disable shard alarms before delete
ALARM_ACTION="disable" $LOCAL_PATH/../../scripts/update-shard-alarm.sh $SSH_USER

# now login and stop nginx on the shard, to ensure no more conferences go to it
$LOCAL_PATH/../../scripts/stop-shard-services.sh $SHARD $SSH_USER


[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"

[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"

[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"

[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/shards/$SHARD/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH/destroy"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH/destroy"
fi

#Use -force-copy option to answer "yes" to the migration question, to confirm migration of workspace states
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
  exit 0
else
  echo "Terraform failed to delete cleanly, dumping existing state"
  # list existing instances in shard
  terraform $TF_GLOBALS_CHDIR show -json $TF_POST_PARAMS
  # sleep requisite time
  sleep 1200
  # re-run terraform destroy command
  terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

  exit $?
fi