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

source $LOCAL_PATH/../clouds/all.sh

[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

source $LOCAL_PATH../clouds/$CLOUD_NAME.sh

describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_ID")
if [ $? -eq 0 ]; then
  XMPP_SERVER_PUBLIC_IP=$(echo "$describe_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"XMPPServerPublicIP\")) | .[].OutputValue")
  if [ ! -z "$XMPP_SERVER_PUBLIC_IP" ]; then
    export XMPP_HOST_PUBLIC_IP_ADDRESS=$XMPP_SERVER_PUBLIC_IP
  fi
fi

SHARD_NAME=$(echo "$describe_stack" | jq -r ".Stacks[].Tags | map(select(.Key==\"Name\")) | .[].Value")
if [ ! -z "$SHARD_NAME" ]; then
  export SHARD=$SHARD_NAME
else
  echo "Error. SHARD_NAME is empty"
  exit 213
fi

export JVBS_POSTINSTALL_STATUS_FILE="/tmp/${SHARD}_jvbs_postinstall_status.txt"
[ -e "$JVBS_POSTINSTALL_STATUS_FILE" ] && rm "$JVBS_POSTINSTALL_STATUS_FILE"

export SHARD_ROLE=${SHARD_ROLE}
export ORACLE_REGION=$ORACLE_REGION
export ORACLE_GIT_BRANCH=${ORACLE_GIT_BRANCH}
export IMAGE_OCID=${JVB_IMAGE_OCID}
export JVB_VERSION=${JVB_VERSION}
export CLOUD_NAME=${CLOUD_NAME}

$LOCAL_PATH/../terraform/create-jvb-stack/create-jvb-stack-oracle.sh ubuntu

if [ ! -e "$JVBS_POSTINSTALL_STATUS_FILE" ]; then
  echo "Could not find the JVB postinstall result file: $JVBS_POSTINSTALL_STATUS_FILE"
  echo "JVBs weren't deployed or the deploy did not work as expected."
  exit 217
fi

export COUNT_JVBS_STATUS_UP=$(grep -c "status: done" "$JVBS_POSTINSTALL_STATUS_FILE")
echo JVB_COUNT_STATUS_UP "$COUNT_JVBS_STATUS_UP"

if [ "$COUNT_JVBS_STATUS_UP" == "$INSTANCE_POOL_SIZE" ]; then
  echo "scale down AWS bridges"
  EXTRA_PARAMS=''

  export DESIRED=0
  export MIN=0
  export MAX=0

  [ ! -z "$MAX" ] && EXTRA_PARAMS="$EXTRA_PARAMS --max $MAX"
  [ ! -z "$MIN" ] && EXTRA_PARAMS="$EXTRA_PARAMS --min $MIN"
  [ ! -z "$EC2_REGION" ] && EXTRA_PARAMS="$EXTRA_PARAMS --region $EC2_REGION"
  [ ! -z "$RELEASE_NUMBER" ] && EXTRA_PARAMS="$EXTRA_PARAMS --release_number $RELEASE_NUMBER"

  $LOCAL_PATH/asg.py --scale --environment "$HCV_ENVIRONMENT" --shard "$SHARD_NAME" --role JVB --desired $DESIRED $EXTRA_PARAMS

  if [ $? -eq 0 ]; then
    echo "SUCCESS SCALING GROUPS"
    exit 0
  else
    echo "FAILED SCALING GROUPS"
    exit 11
  fi
else
  echo "FAILED TO SCALE UP TO EXPECTED SIZE $INSTANCE_POOL_SIZE, GOT TO $COUNT_JVBS_STATUS_UP"
  exit 12
fi
