#!/bin/bash

set -x

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

source $LOCAL_PATH/../clouds/all.sh

[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD
[ -z "$CORE_CLOUD_PROVIDER" ] && CORE_CLOUD_PROVIDER="aws"

source $LOCAL_PATH/../clouds/$CLOUD_NAME.sh

#Generates one or more cloudformation stacks
#export SHARD_CREATE_OUTPUT_FILE=../../../test-results/shard_create_output.txt
#export NEW_SHARDS_FILE=../../../test-results/new_shards.properties

[ -e $SHARD_CREATE_OUTPUT_FILE ] && rm $SHARD_CREATE_OUTPUT_FILE
[ -e $NEW_SHARDS_FILE ] && rm $NEW_SHARDS_FILE

$LOCAL_PATH/new-shards.sh $1

if [ $? -eq 0 ]; then
  #if successful, build a properties file with a list of the new shards in the SHARDS variable, for use in other jobs
  $LOCAL_PATH/make-shard-properties.sh $SHARD_CREATE_OUTPUT_FILE > $NEW_SHARDS_FILE

  source $NEW_SHARDS_FILE

  if [ "$CORE_CLOUD_PROVIDER" == "aws" ]; then
    #Now wait on the shards and end based on their success/failure
    $LOCAL_PATH/wait-new-shards.sh $SHARD_CREATE_OUTPUT_FILE

    exit $?
  fi
else
  exit $?
fi
