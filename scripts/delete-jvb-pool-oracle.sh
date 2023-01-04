#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

if [ -z "$JVB_POOL_NAME" ]; then
  if [ -z "$ENVIRONMENT" ]; then
      echo "no ENVIRONMENT set"
      exit 2
  fi
  if [ -z "$RELEASE_NUMBER" ]; then
      echo "no RELEASE_NUMBER set"
      exit 2
  fi
  if [ -z "$ORACLE_REGION" ]; then
      if [ ! -z "$CLOUD_NAME" ]; then
        source ../all/clouds/"$CLOUD_NAME".sh
      fi
    if [ -z "$ORACLE_REGION" ]; then
      echo "no ORACLE_REGION set"
      exit 2
    fi
  fi

  [ -z "$JVB_POOL_MODE" ] && export JVB_POOL_MODE="global"

  [ -z "$SHARD_BASE" ] && SHARD_BASE="$ENVIRONMENT"

  JVB_POOL_NAME="$SHARD_BASE-$ORACLE_REGION-$JVB_POOL_MODE-$RELEASE_NUMBER"
fi

if [ ! -z "$JVB_POOL_NAME" ]; then
  export SHARD=$JVB_POOL_NAME
  export SHARD_NAME=$SHARD
else
  echo "Error. JVB_POOL_NAME is empty"
  exit 213
fi

$LOCAL_PATH/delete-shard-custom-jvbs-oracle.sh
exit $?