#!/bin/bash
set -x

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

[ -z "$NOMAD_POOL_TYPE" ] && export NOMAD_POOL_TYPE="general"

[ -z "$POSTINSTALL_STATUS_FILE" ] && export POSTINSTALL_STATUS_FILE="$(dirname $SHARD_CREATE_OUTPUT_FILE)/postinstall_status-$SHARD_NAME.txt"


# create shard via nomad
SHARD="$SHARD_NAME" SHARD_ID="$SHARD_NUMBER" $LOCAL_PATH/deploy-nomad-shard-backend.sh

if [ $? -gt 0 ]; then
  echo "ERROR: Nomad shard creation failed, exiting"
  exit 5
fi

# create health check and alarms via terraform
#$LOCAL_PATH/../terraform/shard-nomad/create-shard-nomad-oracle.sh

if [ $? -eq 0 ]; then
    # finished building shard so write to shard create output
    echo "{\"StackId\":\"oracle/$SHARD_NAME\"}" >> $SHARD_CREATE_OUTPUT_FILE
    exit 0
else
    echo "Failed creating shard core"
    exit 2
fi