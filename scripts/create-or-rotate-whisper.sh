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


[ -z "$CLOUD_NAME" ] && CLOUD_NAME="oracle"

source $LOCAL_PATH/../clouds/"$CLOUD_NAME".sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="$RELEASE_BRANCH"


[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"


export AUTOSCALER_BACKEND="${ENVIRONMENT}-${ORACLE_REGION}"
export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME"

[ -z $ENABLE_AUTO_SCALE ] && ENABLE_AUTO_SCALE="false"
[ -z $ENABLE_LAUNCH ] && ENABLE_LAUNCH="false"

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

[ -z "$TAG_NAMESPACE" ] && TAG_NAMESPACE="jitsi"

export ORACLE_REGION=$ORACLE_REGION
export ORACLE_GIT_BRANCH=${ORACLE_GIT_BRANCH}
export IMAGE_OCID=${WHISPER_IMAGE_OCID}
export TAG_NAMESPACE=${TAG_NAMESPACE}

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="oracle"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh


echo "Creating whisper configuration"
$LOCAL_PATH/../terraform/nomad-whisper/create-nomad-whisper-configuration.sh $SSH_USER
if [ $? == 0 ]; then
    echo "Whisper instance configuration created successfully"
else
    echo "Failed to create whisper instance configuration"
    exit 214
fi

INSTANCE_CONFIGURATION=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."role" == "whisper-pool"]' | jq .[0])

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

SCALE_INCREASE_RATE=1
SCALE_DECREASE_RATE=1
GRACE_PERIOD_TTL_SEC=600
PROTECTED_TTL_SEC=200
MIN_COUNT=1
MAX_COUNT=2
SCALE_UP_THRESHOLD=0.6
SCALE_DOWN_THRESHOLD=0.1
SCALE_PERIOD=60
SCALE_UP_PERIODS_COUNT=2
SCALE_DOWN_PERIODS_COUNT=10
[ -z $DESIRED_COUNT ] && DESIRED_COUNT=$MIN_COUNT



export TYPE="whisper"
export INSTANCE_CONFIGURATION_ID=$INSTANCE_CONFIGURATION_ID
export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-whisper"
export ENABLE_AUTO_SCALE=${ENABLE_AUTO_SCALE}
export ENABLE_LAUNCH=${ENABLE_LAUNCH}
export ENABLE_SCHEDULER="false"
export ENABLE_RECONFIGURATION="false"
export GRACE_PERIOD_TTL_SEC=${GRACE_PERIOD_TTL_SEC}
export PROTECTED_TTL_SEC=${PROTECTED_TTL_SEC}
export MAX_COUNT=${MAX_COUNT}
export MIN_COUNT=${MIN_COUNT}
export DESIRED_COUNT=${DESIRED_COUNT}
export SCALE_UP_THRESHOLD=${SCALE_UP_THRESHOLD}
export SCALE_DOWN_THRESHOLD=${SCALE_DOWN_THRESHOLD}
export SCALING_INCREASE_RATE=${SCALE_INCREASE_RATE}
export SCALING_DECREASE_RATE=${SCALE_DECREASE_RATE}
export SCALE_PERIOD=${SCALE_PERIOD}
export SCALE_UP_PERIODS_COUNT=${SCALE_UP_PERIODS_COUNT}
export SCALE_DOWN_PERIODS_COUNT=${SCALE_DOWN_PERIODS_COUNT}

[ -z "$WAIT_FOR_POSTINSTALL" ] && WAIT_FOR_POSTINSTALL="TRUE"
[ -z "$SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS" ] && SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS=480

####

echo "Creating Whisper autoscaling group"
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
  echo "Wait for Whisper instances to launch"

  if [ $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS -gt 0 ]; then
    echo "Sleeping for $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS seconds before checking postinstall result"
    sleep $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS
  fi

  echo "Checking postinstall result and waiting for it to complete..."
  export GROUP_NAME
  export SIDECAR_ENV_VARIABLES
  export AUTOSCALER_URL
  export TOKEN
  export EXPECTED_COUNT="$DESIRED_COUNT"
  export CHECK_SCALE_UP="true"
  $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh
  POSTINSTALL_RESULT=$?

  if [ $POSTINSTALL_RESULT -gt 0 ]; then
    echo "Posinstall did not succeeded for $GROUP_NAME. Exiting."
    exit 214
  fi
fi
