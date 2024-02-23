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


[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

if [ -z "$NOMAD_JVB_FLAG" ]; then
  JVB_NOMAD_VARIABLE="jvb_enable_nomad"

  NOMAD_JVB_FLAG="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
  if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
    NOMAD_JVB_FLAG="$(cat $CONFIG_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
  fi
  if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
    NOMAD_JVB_FLAG=
  fi
fi

[ -z "$NOMAD_JVB_FLAG" ] && NOMAD_JVB_FLAG="false"


if [[ "$NOMAD_JVB_FLAG" == "true" ]]; then
  JVB_VERSION="latest"
  export AUTOSCALER_TYPE="nomad"
  export JVB_POOL_MODE="nomad"
  [ -z "$GROUP_NAME_SUFFIX" ] && GROUP_NAME_SUFFIX="JVBNomadPoolCustomGroup"
  echo "Using Nomad AUTOSCALER_URL"
  export AUTOSCALER_BACKEND="${ENVIRONMENT}-${ORACLE_REGION}"
  export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$GROUP_NAME_SUFFIX" ] && GROUP_NAME_SUFFIX="JVBCustomGroup"

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

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="oracle"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
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
  INSTANCE_CONFIG_RELEASE_NUMBER=$(echo "$INSTANCE_CONFIGURATION" | jq -r '."defined-tags".'\""$TAG_NAMESPACE"\"'."release_number"')

elif [[ "$CLOUD_PROVIDER" == "nomad" ]]; then
  # deploy nomad job definition for pool
  $LOCAL_PATH/deploy-nomad-jvb.sh

  if [ $? -gt 0 ]; then
      echo "Failed to deploy nomad job, exiting..."
      exit 222
  fi

  # wait 90 seconds before checking postinstall
  export SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS=90

  export NOMAD_JOB_NAME="jvb-${SHARD}"
  export NOMAD_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
  export INSTANCE_CONFIGURATION_ID="${NOMAD_URL}|${NOMAD_JOB_NAME}"
  export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
  INSTANCE_CONFIG_RELEASE_NUMBER=$RELEASE_NUMBER
else
  echo "No valid CLOUD_PROVIDER found. Exiting..."
  exit 203
fi

echo "Instance configuration id is: $INSTANCE_CONFIGURATION_ID"


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

if [ -z "$REGION_JVB_SCALING_INCREASE_RATE" ]; then
  if [ -z "$JVB_SCALING_INCREASE_RATE" ]; then
    if [ "$JVB_POOL_MODE" == "remote"  ]; then
      JVB_SCALING_INCREASE_RATE=$DEFAULT_REMOTE_JVB_SCALING_INCREASE_RATE
    else
      JVB_SCALING_INCREASE_RATE=$DEFAULT_RELEASE_JVB_SCALING_INCREASE_RATE
    fi
  fi
else
  JVB_SCALING_INCREASE_RATE=$REGION_JVB_SCALING_INCREASE_RATE
fi

if [ -z "$REGION_JVB_SCALING_DECREASE_RATE" ]; then
  if [ -z "$JVB_SCALING_DECREASE_RATE" ]; then
    if [ "$JVB_POOL_MODE" == "remote"  ]; then
      JVB_SCALING_DECREASE_RATE=$DEFAULT_REMOTE_JVB_SCALING_DECREASE_RATE
    else
      JVB_SCALING_DECREASE_RATE=$DEFAULT_RELEASE_JVB_SCALING_DECREASE_RATE
    fi
  fi
else 
  JVB_SCALING_DECREASE_RATE=$REGION_JVB_SCALING_DECREASE_RATE
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
[ -z "$JVB_SCALE_UP_THRESHOLD" ] && JVB_SCALE_UP_THRESHOLD=0.3
# If JVB load(stress) is lower than JVB_SCALE_DOWN_THRESHOLD, the autoscaler should scale down
[ -z "$JVB_SCALE_DOWN_THRESHOLD" ] && JVB_SCALE_DOWN_THRESHOLD=0.1

[ -z "$JVB_SCALE_PERIOD" ] && JVB_SCALE_PERIOD=60
[ -z "$JVB_SCALE_UP_PERIODS_COUNT" ] && JVB_SCALE_UP_PERIODS_COUNT=2
[ -z "$JVB_SCALE_DOWN_PERIODS_COUNT" ] && JVB_SCALE_DOWN_PERIODS_COUNT=10
[ -z "$AUTOSCALER_TYPE" ] && AUTOSCALER_TYPE="JVB"

export TYPE="$AUTOSCALER_TYPE"
export INSTANCE_CONFIGURATION_ID=$INSTANCE_CONFIGURATION_ID
export TAG_RELEASE_NUMBER=$INSTANCE_CONFIG_RELEASE_NUMBER
export GROUP_NAME="${JVB_POOL_NAME}-${GROUP_NAME_SUFFIX}"
export ENABLE_AUTO_SCALE=${JVB_ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${JVB_ENABLE_LAUNCH}
export ENABLE_SCHEDULER=${JVB_ENABLE_SCHEDULER}
export ENABLE_RECONFIGURATION=${JVB_ENABLE_RECONFIGURATION}
export GRACE_PERIOD_TTL_SEC=${JVB_GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${JVB_PROTECTED_TTL_SEC}
export MAX_COUNT=${AUTOSCALER_RELEASE_JVB_MAX_COUNT}
export MIN_COUNT=${AUTOSCALER_RELEASE_JVB_MIN_COUNT}
export DESIRED_COUNT=${RELEASE_INSTANCE_POOL_SIZE}
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
