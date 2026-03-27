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

source "$LOCAL_PATH/../clouds/$CLOUD_NAME.sh"

# pull in oracle-specific definitions
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$GRID_NAME" ]; then
  echo "No GRID_NAME found.  Exiting..."
  exit 204
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

# Instance configuration IDs should be passed in by the caller (from terraform output)
if [ -z "$INSTANCE_CONFIGURATION_ID_X86" ]; then
  echo "No INSTANCE_CONFIGURATION_ID_X86 provided. Exiting..."
  exit 205
fi

if [ -z "$INSTANCE_CONFIGURATION_ID_ARM" ]; then
  echo "No INSTANCE_CONFIGURATION_ID_ARM provided. Exiting..."
  exit 206
fi

# Derive the selenium grid URL from the hub DNS name
[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"
[ -z "$SELENIUM_GRID_URL" ] && SELENIUM_GRID_URL="http://${ENVIRONMENT}-${ORACLE_REGION}-${GRID_NAME}-grid.${DNS_ZONE_NAME}:4444"

#### Custom autoscaler properties
[ -z "$GRID_ENABLE_AUTO_SCALE" ] && GRID_ENABLE_AUTO_SCALE=true
[ -z "$GRID_ENABLE_LAUNCH" ] && GRID_ENABLE_LAUNCH=true
[ -z "$GRID_ENABLE_SCHEDULER" ] && GRID_ENABLE_SCHEDULER=false
[ -z "$GRID_ENABLE_RECONFIGURATION" ] && GRID_ENABLE_RECONFIGURATION=false
[ -z "$GRID_GRACE_PERIOD_TTL_SEC" ] && GRID_GRACE_PERIOD_TTL_SEC=480
[ -z "$GRID_PROTECTED_TTL_SEC" ] && GRID_PROTECTED_TTL_SEC=600

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=1

[ -z "$AUTOSCALER_GRID_MIN_COUNT" ] && AUTOSCALER_GRID_MIN_COUNT="$INSTANCE_POOL_SIZE"
[ -z "$AUTOSCALER_GRID_MAX_COUNT" ] && AUTOSCALER_GRID_MAX_COUNT=5

# Queue-based thresholds: scale up when queue > 5, scale down when queue < 1
[ -z "$GRID_SCALE_UP_THRESHOLD" ] && GRID_SCALE_UP_THRESHOLD=5
[ -z "$GRID_SCALE_DOWN_THRESHOLD" ] && GRID_SCALE_DOWN_THRESHOLD=0

# scale up/down by 1 at a time by default
[ -z "$GRID_SCALING_INCREASE_RATE" ] && GRID_SCALING_INCREASE_RATE=1
[ -z "$GRID_SCALING_DECREASE_RATE" ] && GRID_SCALING_DECREASE_RATE=1

[ -z "$GRID_SCALE_PERIOD" ] && GRID_SCALE_PERIOD=60
[ -z "$GRID_SCALE_UP_PERIODS_COUNT" ] && GRID_SCALE_UP_PERIODS_COUNT=2
[ -z "$GRID_SCALE_DOWN_PERIODS_COUNT" ] && GRID_SCALE_DOWN_PERIODS_COUNT=10

export CLOUD_PROVIDER="oracle"
export TYPE="selenium-grid"
export SELENIUM_GRID_URL
export ENABLE_AUTO_SCALE=${GRID_ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${GRID_ENABLE_LAUNCH}
export ENABLE_SCHEDULER=${GRID_ENABLE_SCHEDULER}
export ENABLE_RECONFIGURATION=${GRID_ENABLE_RECONFIGURATION}
export GRACE_PERIOD_TTL_SEC=${GRID_GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${GRID_PROTECTED_TTL_SEC}
export MAX_COUNT=${AUTOSCALER_GRID_MAX_COUNT}
export MIN_COUNT=${AUTOSCALER_GRID_MIN_COUNT}
export DESIRED_COUNT=${INSTANCE_POOL_SIZE}
export SCALE_UP_THRESHOLD=${GRID_SCALE_UP_THRESHOLD}
export SCALE_DOWN_THRESHOLD=${GRID_SCALE_DOWN_THRESHOLD}
export SCALING_INCREASE_RATE=${GRID_SCALING_INCREASE_RATE}
export SCALING_DECREASE_RATE=${GRID_SCALING_DECREASE_RATE}
export SCALE_PERIOD=${GRID_SCALE_PERIOD}
export SCALE_UP_PERIODS_COUNT=${GRID_SCALE_UP_PERIODS_COUNT}
export SCALE_DOWN_PERIODS_COUNT=${GRID_SCALE_DOWN_PERIODS_COUNT}

# Create x86 autoscaler group
export INSTANCE_CONFIGURATION_ID="$INSTANCE_CONFIGURATION_ID_X86"
export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-${GRID_NAME}-SeleniumGridX86CustomGroup"
export TAG_RELEASE_NUMBER=""

echo "Creating selenium-grid x86 autoscaler group"
$LOCAL_PATH/custom-autoscaler-create-group.sh
CREATE_GROUP_RESULT="$?"

if [ $CREATE_GROUP_RESULT -gt 0 ]; then
  echo "Failed to create the custom autoscaler group $GROUP_NAME. Exiting."
  exit 213
fi

# Create ARM autoscaler group
export INSTANCE_CONFIGURATION_ID="$INSTANCE_CONFIGURATION_ID_ARM"
export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-${GRID_NAME}-SeleniumGridArmCustomGroup"

echo "Creating selenium-grid ARM autoscaler group"
$LOCAL_PATH/custom-autoscaler-create-group.sh
CREATE_GROUP_RESULT="$?"

if [ $CREATE_GROUP_RESULT -gt 0 ]; then
  echo "Failed to create the custom autoscaler group $GROUP_NAME. Exiting."
  exit 214
fi

echo "Selenium grid autoscaler groups created successfully"
