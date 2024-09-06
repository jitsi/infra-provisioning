#!/bin/bash
set -x

# This script is run directly from Jenkins job

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$HCV_ENVIRONMENT" ] && HCV_ENVIRONMENT="$ENVIRONMENT"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

echo "deleting shards: $SHARDS"

for x in $SHARDS; do
  AWS_SHARD_DELETE_SUCCESS=0
  SHARD_DELETE_SUCCESS=0
  SHARD_CORE_CLOUD_PROVIDER=$(SHARD=$x ENVIRONMENT=$HCV_ENVIRONMENT $LOCAL_PATH/shard.sh core_provider $SSH_USER)

  if [ "$SHARD_CORE_CLOUD_PROVIDER" == "aws" ]; then
    SHARD_CLOUD_PROVIDER=$CLOUD_PROVIDER
    [ -z "$SHARD_CLOUD_PROVIDER" ] && SHARD_CLOUD_PROVIDER=$($LOCAL_PATH/shard.py --shard_provider --environment $HCV_ENVIRONMENT --shard $x)
    SHARD=$x $LOCAL_PATH/delete-shard.sh $SSH_USER || SHARD_DELETE_SUCCESS=1
  fi
  if [ "$SHARD_CORE_CLOUD_PROVIDER" == "oracle" ]; then
    SHARD_CLOUD_PROVIDER="oracle"
    SHARD=$x $LOCAL_PATH/../terraform/shard-core/destroy-shard-core-oracle.sh $SSH_USER || SHARD_DELETE_SUCCESS=1
  fi
  if [ "$SHARD_CORE_CLOUD_PROVIDER" == "nomad" ]; then
    echo "Skipping nomad delete, not yet supported"
    SHARD_CLOUD_PROVIDER="oracle"
#    SHARD=$x $LOCAL_PATH/../terraform/shard-nomad/destroy-shard-nomad-oracle.sh $SSH_USER || SHARD_DELETE_SUCCESS=1
    SHARD=$x $LOCAL_PATH/delete-nomad-shard.sh || SHARD_DELETE_SUCCESS=1
  fi

  if [ "$SHARD_CLOUD_PROVIDER" == 'oracle' ]; then
    if [ "$SHARD_DELETE_SUCCESS" -eq 0 ]; then
      # for oracle, try to delete both the group and the static instance pool
      echo "Deleting custom JVB group, if any, and its associated instance configuration, if not used by another pool..."
      SHARD_CORE_CLOUD_PROVIDER=$SHARD_CORE_CLOUD_PROVIDER SHARD=$x $LOCAL_PATH/delete-shard-custom-jvbs-oracle.sh

      # echo "Deleting JVB instance pool, if any..."
      # SHARD_CORE_CLOUD_PROVIDER=$SHARD_CORE_CLOUD_PROVIDER SHARD=$x $LOCAL_PATH/../terraform/destroy-jvb-stack/destroy-jvb-stack-oracle.sh >>../../../test-results/shard_delete_jvb_oracle_output.txt
    else
      echo "Skipped deleting JVB instance pool for shard $x" >> $LOCAL_PATH/../../test-results/shard_delete_jvb_oracle_output.txt
    fi
  fi
done

exit $?
