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

source $LOCAL_PATH/../clouds/"$CLOUD_NAME".sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER=0

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="$RELEASE_BRANCH"

[ -z "$JVB_POOL_MODE" ] && export JVB_POOL_MODE="global"

[ -z "$JVB_POOL_STATUS" ] && export JVB_POOL_STATUS="ready"

[ -z "$SHARD_BASE" ] && SHARD_BASE="$ENVIRONMENT"

[ -z "$JVB_POOL_NAME" ] && JVB_POOL_NAME="$SHARD_BASE-$ORACLE_REGION-$JVB_POOL_MODE-$RELEASE_NUMBER"

if [ ! -z "$JVB_POOL_NAME" ]; then
  export SHARD=$JVB_POOL_NAME
  export SHARD_NAME=$SHARD
else
  echo "Error. JVB_POOL_NAME is empty"
  exit 213
fi

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
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
$LOCAL_PATH/../terraform/create-jvb-instance-configuration/create-jvb-instance-configuration.sh $SSH_USER
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

# set jvb pool consul k/v status
JVB_POOL_NAME="$JVB_POOL_NAME" $LOCAL_PATH/consul-set-jvb-pool-status.sh $JVB_POOL_STATUS $SSH_USER

# check regional settings for JVB pool sizes, use if found
REGION_JVB_POOL_SIZE_FILE="./sites/$ENVIRONMENT/jvb-pool-sizes-by-region"

if [ -f "$REGION_JVB_POOL_SIZE_FILE" ]; then

  REGION_JVB_POOL_SIZE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $ORACLE_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
  [ ! -z "$REGION_JVB_POOL_SIZE" ] && DEFAULT_AUTOSCALER_RELEASE_JVB_POOL_SIZE="$REGION_JVB_POOL_SIZE"

  REGION_JVB_POOL_MAX_SIZE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $ORACLE_REGION | awk 'BEGIN { FS = "|" } ; {print $3}')
  [ ! -z "$REGION_JVB_POOL_MAX_SIZE" ] && AUTOSCALER_RELEASE_JVB_MAX_COUNT="$REGION_JVB_POOL_MAX_SIZE"

  REGION_JVB_SCALING_INCREASE_RATE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $ORACLE_REGION | awk 'BEGIN { FS = "|" } ; {print $4}')

  REGION_JVB_SCALING_DECREASE_RATE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $ORACLE_REGION | awk 'BEGIN { FS = "|" } ; {print $5}')
fi

# scale up remote pools by 1 at a time by default unless overridden
[ -z "$DEFAULT_REMOTE_JVB_SCALING_INCREASE_RATE" ] && DEFAULT_REMOTE_JVB_SCALING_INCREASE_RATE=1
# scale up all other pools by 1 at a time by default unless overridden
[ -z "$DEFAULT_JVB_SCALING_INCREASE_RATE" ] && DEFAULT_JVB_SCALING_INCREASE_RATE=1
[ -z "$DEFAULT_RELEASE_JVB_SCALING_INCREASE_RATE" ] && DEFAULT_RELEASE_JVB_SCALING_INCREASE_RATE=$DEFAULT_JVB_SCALING_INCREASE_RATE


# scale up remote pools by 1 at a time by default unless overridden
[ -z "$DEFAULT_REMOTE_JVB_SCALING_DECREASE_RATE" ] && DEFAULT_REMOTE_JVB_SCALING_DECREASE_RATE=1
# scale up all other pools by 1 at a time by default unless overridden
[ -z "$DEFAULT_JVB_SCALING_DECREASE_RATE" ] && DEFAULT_JVB_SCALING_DECREASE_RATE=1
[ -z "$DEFAULT_RELEASE_JVB_SCALING_DECREASE_RATE" ] && DEFAULT_RELEASE_JVB_SCALING_DECREASE_RATE=$DEFAULT_JVB_SCALING_DECREASE_RATE

if [ -z "$REGION_JVB_SCALING_INCREASE_RATE"]; then
  if [ -z "$RELEASE_JVB_SCALING_INCREASE_RATE" ]; then
    if [ "$JVB_POOL_MODE" == "remote"  ]; then
      RELEASE_JVB_SCALING_INCREASE_RATE=$DEFAULT_REMOTE_JVB_SCALING_INCREASE_RATE
    else
      RELEASE_JVB_SCALING_INCREASE_RATE=$DEFAULT_RELEASE_JVB_SCALING_INCREASE_RATE
    fi
  fi
else
  RELEASE_JVB_SCALING_INCREASE_RATE=$REGION_JVB_SCALING_INCREASE_RATE
fi

if [ -z "$REGION_JVB_SCALING_INCREASE_RATE"]; then
  if [ -z "$RELEASE_JVB_SCALING_DECREASE_RATE" ]; then
    if [ "$JVB_POOL_MODE" == "remote"  ]; then
      RELEASE_JVB_SCALING_DECREASE_RATE=$DEFAULT_REMOTE_JVB_SCALING_DECREASE_RATE
    else
      RELEASE_JVB_SCALING_DECREASE_RATE=$DEFAULT_RELEASE_JVB_SCALING_DECREASE_RATE
    fi
  fi
else 
  RELEASE_JVB_SCALING_DECREASE_RATE=$REGION_JVB_SCALING_DECREASE_RATE
fi

#### Custom autoscaler properties
[ -z "$JVB_ENABLE_AUTO_SCALE" ] && JVB_ENABLE_AUTO_SCALE=true
[ -z "$JVB_ENABLE_LAUNCH" ] && JVB_ENABLE_LAUNCH=true
[ -z "$JVB_ENABLE_SCHEDULER" ] && JVB_ENABLE_SCHEDULER=true
# by default JVB pools should enable reconfiguration
[ -z "$JVB_ENABLE_RECONFIGURATION" ] && JVB_ENABLE_RECONFIGURATION=true
[ -z "$JVB_GRACE_PERIOD_TTL_SEC" ] && JVB_GRACE_PERIOD_TTL_SEC=600
[ -z "$JVB_PROTECTED_TTL_SEC" ] && JVB_PROTECTED_TTL_SEC=900

[ -z "$RELEASE_INSTANCE_POOL_SIZE" ] && RELEASE_INSTANCE_POOL_SIZE="$DEFAULT_AUTOSCALER_RELEASE_JVB_POOL_SIZE"
[ -z "$RELEASE_INSTANCE_POOL_SIZE" ] && RELEASE_INSTANCE_POOL_SIZE=2
[ -z "$AUTOSCALER_RELEASE_JVB_MIN_COUNT" ] && AUTOSCALER_RELEASE_JVB_MIN_COUNT="$RELEASE_INSTANCE_POOL_SIZE"
[ -z "$AUTOSCALER_RELEASE_JVB_MAX_COUNT" ] && AUTOSCALER_RELEASE_JVB_MAX_COUNT=8

# If JVB load(stress) is higher than JVB_SCALE_UP_THRESHOLD, the autoscaler should scale up
[ -z "$RELEASE_JVB_SCALE_UP_THRESHOLD" ] && RELEASE_JVB_SCALE_UP_THRESHOLD=0.3
# If JVB load(stress) is lower than JVB_SCALE_DOWN_THRESHOLD, the autoscaler should scale down
[ -z "$RELEASE_JVB_SCALE_DOWN_THRESHOLD" ] && RELEASE_JVB_SCALE_DOWN_THRESHOLD=0.1

[ -z "$RELEASE_JVB_SCALE_PERIOD" ] && RELEASE_JVB_SCALE_PERIOD=60
[ -z "$RELEASE_JVB_SCALE_UP_PERIODS_COUNT" ] && RELEASE_JVB_SCALE_UP_PERIODS_COUNT=2
[ -z "$RELEASE_JVB_SCALE_DOWN_PERIODS_COUNT" ] && RELEASE_JVB_SCALE_DOWN_PERIODS_COUNT=10

export CLOUD_PROVIDER="oracle"
export TYPE="JVB"
export INSTANCE_CONFIGURATION_ID=$INSTANCE_CONFIGURATION_ID
export TAG_RELEASE_NUMBER=$INSTANCE_CONFIG_RELEASE_NUMBER
export GROUP_NAME=${JVB_POOL_NAME}-"JVBCustomGroup"
export ENABLE_AUTO_SCALE=${JVB_ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${JVB_ENABLE_LAUNCH}
export ENABLE_SCHEDULER=${JVB_ENABLE_SCHEDULER}
export ENABLE_RECONFIGURATION=${JVB_ENABLE_RECONFIGURATION}
export GRACE_PERIOD_TTL_SEC=${JVB_GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${JVB_PROTECTED_TTL_SEC}
export MAX_COUNT=${AUTOSCALER_RELEASE_JVB_MAX_COUNT}
export MIN_COUNT=${AUTOSCALER_RELEASE_JVB_MIN_COUNT}
export DESIRED_COUNT=${RELEASE_INSTANCE_POOL_SIZE}
export SCALE_UP_THRESHOLD=${RELEASE_JVB_SCALE_UP_THRESHOLD}
export SCALE_DOWN_THRESHOLD=${RELEASE_JVB_SCALE_DOWN_THRESHOLD}
export SCALING_INCREASE_RATE=${RELEASE_JVB_SCALING_INCREASE_RATE}
export SCALING_DECREASE_RATE=${RELEASE_JVB_SCALING_DECREASE_RATE}
export SCALE_PERIOD=${RELEASE_JVB_SCALE_PERIOD}
export SCALE_UP_PERIODS_COUNT=${RELEASE_JVB_SCALE_UP_PERIODS_COUNT}
export SCALE_DOWN_PERIODS_COUNT=${RELEASE_JVB_SCALE_DOWN_PERIODS_COUNT}

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
