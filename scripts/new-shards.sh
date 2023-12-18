#!/bin/bash
set -x #echo on

#takes one parameter, the number of shards to create
#detects the appropriate next shard number and creates it

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

[ -z $GIT_BRANCH ] && GIT_BRANCH='master'

[ -z $SHARD_COUNT ] && SHARD_COUNT=1

[ -z "$CORE_CLOUD_PROVIDER" ] && CORE_CLOUD_PROVIDER="aws"

if [ -n "$CLOUD_NAME" ]; then
  [ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh"
fi

#select new shard numbers if not provided
[ -z "$SHARD_NUMBERS" ] && SHARD_NUMBERS=$(ENVIRONMENT="$ENVIRONMENT" COUNT=$SHARD_COUNT $LOCAL_PATH/shard.sh new $ANSIBLE_SSH_USER)

FINAL_RET=0
if [ $? -eq 0 ]; then
  export CORE_CLOUD_PROVIDER
  export ORACLE_REGION
  export REGION_ALIAS

  for SN in $SHARD_NUMBERS; do
      export SHARD_NAME=$(ENVIRONMENT="$ENVIRONMENT" SHARD_NUMBER="$SN" $LOCAL_PATH/shard.sh name $ANSIBLE_SSH_USER)
      # first mark new shard as drain
      CONSUL_SHARD_STATES_ONLY="true" SHARDS_DRAIN="$SHARD_NAME" scripts/set-signal-shard-states.sh $ANSIBLE_SSH_USER
      #make a new stack for each new shard
      if [[ "$CORE_CLOUD_PROVIDER" == "aws" ]]; then
          SHARD_NUMBER=$SN $LOCAL_PATH/create-app-shard-stack.sh
          RET=$?
      elif [[ "$CORE_CLOUD_PROVIDER" == "oracle" ]]; then
          SHARD_NUMBER=$SN $LOCAL_PATH/create-shard-oracle.sh $ANSIBLE_SSH_USER
          RET=$?
      elif [[ "$CORE_CLOUD_PROVIDER" == "nomad" ]]; then
          SHARD_NUMBER=$SN $LOCAL_PATH/create-shard-nomad.sh $ANSIBLE_SSH_USER
          RET=$?
      else
          echo "Not a supported CORE_CLOUD_PROVIDER: $CORE_CLOUD_PROVIDER"
          RET=3
      fi
      if [[ $RET -gt 0 ]]; then
        FINAL_RET=$RET
      fi
  done
  if [[ $FINAL_RET -eq 0 ]]; then
    echo "Success creating all shards"
  else
    echo "Error creating one or more shards"
  fi
  exit $FINAL_RET
else
  echo "Error creating shard numbers"
  exit 2
fi