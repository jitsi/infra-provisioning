#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

if [ "$SKIP_SHARD_JVBS" == "true" ]; then
  echo "Skipping JVB creation for shards in $ENVIRONMENT since SKIP_SHARD_JVBS=true"
  exit 0
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

source $LOCAL_PATH/../clouds/all.sh

[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

source $LOCAL_PATH/../clouds/"$CLOUD_NAME".sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ ! -z "$STACK_ID" ]; then
  if [[ "$(echo $STACK_ID | cut -d '/' -f1)" == "oracle" ]]; then
    # no STACK_ID provided so assume oracle shard
    echo "STACK_ID starts with oracle, assuming oracle shard"
    SKIP_AWS_SCALE_DOWN=true
    SHARD_NAME="$(echo $STACK_ID | cut -d '/' -f2)"
  else
    describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_ID")
    if [ $? -eq 0 ]; then
      XMPP_SERVER_PUBLIC_IP=$(echo "$describe_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"XMPPServerPublicIP\")) | .[].OutputValue")
      if [ ! -z "$XMPP_SERVER_PUBLIC_IP" ]; then
        export XMPP_HOST_PUBLIC_IP_ADDRESS=$XMPP_SERVER_PUBLIC_IP
      fi
    fi
    SHARD_NAME=$(echo "$describe_stack" | jq -r ".Stacks[].Tags | map(select(.Key==\"Name\")) | .[].Value")
  fi


else
  # no STACK_ID provided so assume oracle shard
  echo "No STACK_ID provided, assuming oracle shard"
  SKIP_AWS_SCALE_DOWN=true
fi

if [ ! -z "$SHARD_NAME" ]; then
  export SHARD=$SHARD_NAME
else
  echo "Error. SHARD_NAME is empty"
  exit 213
fi

export SHARD_ROLE=${SHARD_ROLE}
export ORACLE_REGION=$ORACLE_REGION
export ORACLE_GIT_BRANCH=${ORACLE_GIT_BRANCH}
export IMAGE_OCID=${JVB_IMAGE_OCID}
export JVB_VERSION=${JVB_VERSION}
export CLOUD_NAME=${CLOUD_NAME}
export JVB_AUTOSCALER_ENABLED=true

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

echo "Creating Jvb Instance Configuration"
$LOCAL_PATH/../terraform/create-jvb-instance-configuration/create-jvb-instance-configuration.sh ubuntu
if [ $? == 0 ]; then
  echo "Jvb Instance Configuration was created successfully"
else
  echo "Jvb Instance Configuration failed to create correctly"
  exit 214
fi

INSTANCE_CONFIGURATION=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard" == `'"$SHARD_NAME"'`]' | jq .[0])

if [ -z "$INSTANCE_CONFIGURATION" ]; then
  echo "No Instance configuration was found. Exiting ..."
  exit 201
fi

INSTANCE_CONFIGURATION_ID=$(echo "$INSTANCE_CONFIGURATION" | jq -r '.id')
if [ -z "$INSTANCE_CONFIGURATION_ID" ]; then
  echo "No Instance configuration id was found. Exiting.."
  exit 215
fi
echo "Instance configuration id is: $INSTANCE_CONFIGURATION_ID"

INSTANCE_CONFIG_RELEASE_NUMBER=$(echo "$INSTANCE_CONFIGURATION" | jq -r '."defined-tags".'\""$TAG_NAMESPACE"\"'."release_number"')

#### Custom autoscaler properties
[ -z "$JVB_ENABLE_AUTO_SCALE" ] && JVB_ENABLE_AUTO_SCALE=true
[ -z "$JVB_ENABLE_LAUNCH" ] && JVB_ENABLE_LAUNCH=true
[ -z "$JVB_ENABLE_SCHEDULER" ] && JVB_ENABLE_SCHEDULER=true
[ -z "$JVB_ENABLE_RECONFIGURATION" ] && JVB_ENABLE_RECONFIGURATION=false
[ -z "$JVB_GRACE_PERIOD_TTL_SEC" ] && JVB_GRACE_PERIOD_TTL_SEC=300
[ -z "$JVB_PROTECTED_TTL_SEC" ] && JVB_PROTECTED_TTL_SEC=900

# check regional settings for JVB pool sizes, use if found
REGION_JVB_POOL_SIZE_FILE='./jvb-shard-sizes-by-region'

if [ -f "$REGION_JVB_POOL_SIZE_FILE" ]; then

  REGION_JVB_POOL_SIZE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $EC2_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
  [ ! -z "$REGION_JVB_POOL_SIZE" ] && DEFAULT_AUTOSCALER_JVB_POOL_SIZE="$REGION_JVB_POOL_SIZE"

  REGION_JVB_POOL_MAX_SIZE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $EC2_REGION | awk 'BEGIN { FS = "|" } ; {print $3}')
  [ ! -z "$REGION_JVB_POOL_MAX_SIZE" ] && AUTOSCALER_JVB_MAX_COUNT="$REGION_JVB_POOL_MAX_SIZE"

fi

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=1
[ -z "$AUTOSCALER_JVB_MIN_COUNT" ] && AUTOSCALER_JVB_MIN_COUNT="$INSTANCE_POOL_SIZE"
[ -z "$AUTOSCALER_JVB_MAX_COUNT" ] && AUTOSCALER_JVB_MAX_COUNT=10

# If JVB load(stress) is higher than JVB_SCALE_UP_THRESHOLD, the autoscaler should scale up
[ -z "$JVB_SCALE_UP_THRESHOLD" ] && JVB_SCALE_UP_THRESHOLD=0.3
# If JVB load(stress) is lower than JVB_SCALE_DOWN_THRESHOLD, the autoscaler should scale down
[ -z "$JVB_SCALE_DOWN_THRESHOLD" ] && JVB_SCALE_DOWN_THRESHOLD=0.1

# scale up by 1 at a time by default unless overridden
[ -z "$JVB_SCALING_INCREASE_RATE" ] && JVB_SCALING_INCREASE_RATE=1
# scale down by 1 at a time unless overridden
[ -z "$JVB_SCALING_DECREASE_RATE" ] && JVB_SCALING_DECREASE_RATE=1

[ -z "$JVB_SCALE_PERIOD" ] && JVB_SCALE_PERIOD=60
[ -z "$JVB_SCALE_UP_PERIODS_COUNT" ] && JVB_SCALE_UP_PERIODS_COUNT=2
[ -z "$JVB_SCALE_DOWN_PERIODS_COUNT" ] && JVB_SCALE_DOWN_PERIODS_COUNT=10

export CLOUD_PROVIDER="oracle"
export TYPE="JVB"
export INSTANCE_CONFIGURATION_ID=$INSTANCE_CONFIGURATION_ID
export TAG_RELEASE_NUMBER=$INSTANCE_CONFIG_RELEASE_NUMBER
export GROUP_NAME=${SHARD_NAME}-"JVBCustomGroup"
export ENABLE_AUTO_SCALE=${JVB_ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${JVB_ENABLE_LAUNCH}
export ENABLE_SCHEDULER=${JVB_ENABLE_SCHEDULER}
export ENABLE_RECONFIGURATION=${JVB_ENABLE_RECONFIGURATION}
export GRACE_PERIOD_TTL_SEC=${JVB_GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${JVB_PROTECTED_TTL_SEC}
export MAX_COUNT=${AUTOSCALER_JVB_MAX_COUNT}
export MIN_COUNT=${AUTOSCALER_JVB_MIN_COUNT}
export DESIRED_COUNT=${INSTANCE_POOL_SIZE}
export SCALE_UP_THRESHOLD=${JVB_SCALE_UP_THRESHOLD}
export SCALE_DOWN_THRESHOLD=${JVB_SCALE_DOWN_THRESHOLD}
export SCALING_INCREASE_RATE=${JVB_SCALING_INCREASE_RATE}
export SCALING_DECREASE_RATE=${JVB_SCALING_DECREASE_RATE}
export SCALE_PERIOD=${JVB_SCALE_PERIOD}
export SCALE_UP_PERIODS_COUNT=${JVB_SCALE_UP_PERIODS_COUNT}
export SCALE_DOWN_PERIODS_COUNT=${JVB_SCALE_DOWN_PERIODS_COUNT}

[ -z "$WAIT_FOR_POSTINSTALL" ] && WAIT_FOR_POSTINSTALL="TRUE"
[ -z "$SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS" ] && SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS=480

####

echo "Creating jvb group"
$LOCAL_PATH/custom-autoscaler-create-group.sh
CREATE_GROUP_RESULT="$?"

if [ $CREATE_GROUP_RESULT -gt 0 ]; then
  echo "Failed to create the custom autoscaler group $GROUP_NAME. Exiting."
  exit 213
fi

if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
  echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
  exit 211
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi


if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

if [ $WAIT_FOR_POSTINSTALL == "TRUE" ]; then
  echo "Wait for JVB instances to launch"

  if [ $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS -gt 0 ]; then
    echo "Sleeping for $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS seconds before checking postinstall result"
    sleep $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS
  fi

  echo "Checking postinstall result and waiting for it to complete..."
  export GROUP_NAME
  export SIDECAR_ENV_VARIABLES
  export AUTOSCALER_URL
  export TOKEN
  export EXPECTED_COUNT="$MIN_COUNT"
  export CHECK_SCALE_UP="true"
  $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh
  POSTINSTALL_RESULT=$?

  if [ $POSTINSTALL_RESULT -gt 0 ]; then
    echo "Posinstall did not succeeded for $GROUP_NAME. Exiting."
    exit 214
  fi
fi

if [ -z "$SKIP_AWS_SCALE_DOWN" ]; then

  echo "Scaling down AWS bridges"
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
  echo "SKIPPED SCALING AWS BRIDGES"
  exit 0
fi

