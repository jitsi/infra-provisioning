#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# We need an environment
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

source $LOCAL_PATH/../clouds/all.sh

[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

source "$LOCAL_PATH/../$CLOUD_NAME.sh"

# pull in oracle-specific definitions
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [[ "$JIGASI_TRANSCRIBER_FLAG" == "true" ]]; then
  export SHARD_ROLE="jigasi-transcriber"
  export GROUP_NAME_SUFFIX="TranscriberCustomGroup"
else
  export SHARD_ROLE="jigasi"
  export GROUP_NAME_SUFFIX="JigasiCustomGroup"
fi

export ORACLE_REGION=$ORACLE_REGION
export ORACLE_GIT_BRANCH=${ORACLE_GIT_BRANCH}
export IMAGE_OCID=${JVB_IMAGE_OCID}
export JIGASI_VERSION=${JIGASI_VERSION}
export CLOUD_NAME=${CLOUD_NAME}

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

echo "Creating Jigasi Instance Configuration"
$LOCAL_PATH/../terraform/create-jigasi-instance-configuration/create-jigasi-instance-configuration.sh ubuntu
if [ $? == 0 ]; then
  echo "Jigasi Instance Configuration was created successfully"
else
  echo "Jigasi Instance Configuration failed to create correctly"
  exit 214
fi

INSTANCE_CONFIGURATION=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `'"$SHARD_ROLE"'`]' | jq .[0])

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

INSTANCE_CONFIG_RELEASE_NUMBER=$(echo "$INSTANCE_CONFIGURATION" | jq -r '."defined-tags".'\""$TAG_NAMESPACE"\"'."jigasi_release_number"')

#### Custom autoscaler properties
[ -z "$JIGASI_ENABLE_AUTO_SCALE" ] && JIGASI_ENABLE_AUTO_SCALE=true
[ -z "$JIGASI_ENABLE_LAUNCH" ] && JIGASI_ENABLE_LAUNCH=true
[ -z "$JIGASI_ENABLE_SCHEDULER" ] && JIGASI_ENABLE_SCHEDULER=false
[ -z "$JIGASI_ENABLE_RECONFIGURATION" ] && JIGASI_ENABLE_RECONFIGURATION=false
[ -z "$JIGASI_GRACE_PERIOD_TTL_SEC" ] && JIGASI_GRACE_PERIOD_TTL_SEC=600
[ -z "$JIGASI_PROTECTED_TTL_SEC" ] && JIGASI_PROTECTED_TTL_SEC=900

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE="$DEFAULT_AUTOSCALER_JIGASI_POOL_SIZE"
[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=2
[ -z "$AUTOSCALER_JIGASI_MIN_COUNT" ] && AUTOSCALER_JIGASI_MIN_COUNT="$INSTANCE_POOL_SIZE"
[ -z "$AUTOSCALER_JIGASI_MAX_COUNT" ] && AUTOSCALER_JIGASI_MAX_COUNT=10

# If Jigasi load(stress) is higher than JIGASI_SCALE_UP_THRESHOLD, the autoscaler should scale up
[ -z "$JIGASI_SCALE_UP_THRESHOLD" ] && JIGASI_SCALE_UP_THRESHOLD=0.3
# If Jigasi load(stress) is lower than JIGASI_SCALE_DOWN_THRESHOLD, the autoscaler should scale down
[ -z "$JIGASI_SCALE_DOWN_THRESHOLD" ] && JIGASI_SCALE_DOWN_THRESHOLD=0.1

# scale up by 1 at a time by default unless overridden
[ -z "$JIGASI_SCALING_INCREASE_RATE" ] && JIGASI_SCALING_INCREASE_RATE=1
# scale down by 1 at a time unless overridden
[ -z "$JIGASI_SCALING_DECREASE_RATE" ] && JIGASI_SCALING_DECREASE_RATE=1

[ -z "$JIGASI_SCALE_PERIOD" ] && JIGASI_SCALE_PERIOD=60
[ -z "$JIGASI_SCALE_UP_PERIODS_COUNT" ] && JIGASI_SCALE_UP_PERIODS_COUNT=2
[ -z "$JIGASI_SCALE_DOWN_PERIODS_COUNT" ] && JIGASI_SCALE_DOWN_PERIODS_COUNT=10

export CLOUD_PROVIDER="oracle"
export TYPE="jigasi"
export INSTANCE_CONFIGURATION_ID=$INSTANCE_CONFIGURATION_ID
export TAG_RELEASE_NUMBER=$INSTANCE_CONFIG_RELEASE_NUMBER
export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-${GROUP_NAME_SUFFIX}"
export ENABLE_AUTO_SCALE=${JIGASI_ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${JIGASI_ENABLE_LAUNCH}
export ENABLE_SCHEDULER=${JIGASI_ENABLE_SCHEDULER}
export ENABLE_RECONFIGURATION=${JIGASI_ENABLE_RECONFIGURATION}
export GRACE_PERIOD_TTL_SEC=${JIGASI_GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${JIGASI_PROTECTED_TTL_SEC}
export MAX_COUNT=${AUTOSCALER_JIGASI_MAX_COUNT}
export MIN_COUNT=${AUTOSCALER_JIGASI_MIN_COUNT}
export DESIRED_COUNT=${INSTANCE_POOL_SIZE}
export SCALE_UP_THRESHOLD=${JIGASI_SCALE_UP_THRESHOLD}
export SCALE_DOWN_THRESHOLD=${JIGASI_SCALE_DOWN_THRESHOLD}
export SCALING_INCREASE_RATE=${JIGASI_SCALING_INCREASE_RATE}
export SCALING_DECREASE_RATE=${JIGASI_SCALING_DECREASE_RATE}
export SCALE_PERIOD=${JIGASI_SCALE_PERIOD}
export SCALE_UP_PERIODS_COUNT=${JIGASI_SCALE_UP_PERIODS_COUNT}
export SCALE_DOWN_PERIODS_COUNT=${JIGASI_SCALE_DOWN_PERIODS_COUNT}

[ -z "$WAIT_FOR_POSTINSTALL" ] && WAIT_FOR_POSTINSTALL="TRUE"
[ -z "$SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS" ] && SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS=480

####

echo "Creating jigasi group"
$LOCAL_PATH/custom-autoscaler-create-group.sh
CREATE_GROUP_RESULT="$?"

if [ $CREATE_GROUP_RESULT -gt 0 ]; then
  echo "Failed to create the custom autoscaler group $GROUP_NAME. Exiting."
  exit 213
fi


if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

if [ $WAIT_FOR_POSTINSTALL == "TRUE" ]; then
  echo "Wait for Jigasi instances to launch"

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
  # script is called jvb but has nothing jvb-specific in it, so re-using it here
  $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh
  POSTINSTALL_RESULT=$?

  if [ $POSTINSTALL_RESULT -gt 0 ]; then
    echo "Posinstall did not succeeded for $GROUP_NAME. Exiting."
    exit 214
  fi
fi
