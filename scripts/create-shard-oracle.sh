#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ORACLE_REGION" ]; then
    # no region specified, check for cloud name
    if [ ! -z "$CLOUD_NAME" ]; then
        . $LOCAL_PATH/../clouds/$CLOUD_NAME.sh
    else
        echo "No ORACLE_REGION or CLOUD_NAME provided"
        exit 3
    fi
fi
if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION found, exiting"
    exit 4
else
    export ORACLE_REGION
fi

#Default shard base name to environment name
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT
[ -z "$SHARD_CREATE_OUTPUT_FILE" ] && SHARD_CREATE_OUTPUT_FILE="./shard_create_output.txt"

#shard name ends up like: lonely-us-phoenix-1-s3
if [ -z "$SHARD_NAME" ]; then
    [ -z "$SHARD_NUMBER" ] && SHARD_NUMBER=1
    export SHARD_NAME="${SHARD_BASE}-${ORACLE_REGION}-s${SHARD_NUMBER}"
fi
[ -z "$POSTINSTALL_STATUS_FILE" ] && export POSTINSTALL_STATUS_FILE="$(dirname $SHARD_CREATE_OUTPUT_FILE)/postinstall_status-$SHARD_NAME.txt"

$LOCAL_PATH/../terraform/shard-core/create-shard-core-oracle.sh $1

if [ $? -eq 0 ]; then
    # finished building shard so write to shard create output
    echo "{\"StackId\":\"oracle/$SHARD_NAME\"}" >> $SHARD_CREATE_OUTPUT_FILE
    exit 0
else
    echo "Failed creating shard core"
    exit 2
fi