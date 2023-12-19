#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

CLOUD_PROVIDER="nomad"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
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

[ -z "$JVB_PROTECTED_TTL_SEC" ] && JVB_PROTECTED_TTL_SEC=900

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

# ensure nomad job is defined

$LOCAL_PATH/deploy-nomad-jvb.sh

if [ $? -gt 0 ]; then
    echo "Failed to deploy nomad job, exiting..."
    exit 222
fi

export NOMAD_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
export INSTANCE_CONFIGURATION_ID="${NOMAD_URL}|${NOMAD_JOB_NAME}"
export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
export GROUP_NAME=${JVB_POOL_NAME}-"JVBCustomGroup"

echo "Retrieve instance group details for group $GROUP_NAME"
instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
    echo "No group named $GROUP_NAME was found. Will create one"
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

  echo "Creating group named $GROUP_NAME"
  $LOCAL_PATH/custom-autoscaler-create-group.sh
  CREATE_GROUP_RESULT="$?"

  if [ $CREATE_GROUP_RESULT -gt 0 ]; then
    echo "Failed to create the custom autoscaler group $GROUP_NAME. Exiting."
    exit 213
  fi

elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  EXISTING_INSTANCE_CONFIGURATION_ID=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.instanceConfigurationId")
  EXISTING_MAXIMUM=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.maxDesired")
  if [ -z "$EXISTING_INSTANCE_CONFIGURATION_ID" ] || [ "$EXISTING_INSTANCE_CONFIGURATION_ID" == "null" ]; then
    echo "No Instance Configuration was found on the group details $GROUP_NAME. Exiting.."
    exit 206
  fi

  NEW_INSTANCE_CONFIGURATION_ID="$EXISTING_INSTANCE_CONFIGURATION_ID"

  [ -z "$PROTECTED_INSTANCES_COUNT" ] && PROTECTED_INSTANCES_COUNT=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.minDesired")
  if [ -z "$PROTECTED_INSTANCES_COUNT" ]; then
    echo "Something went wrong, could not extract PROTECTED_INSTANCES_COUNT from instanceGroup.scalingOptions.minDesired";
    exit 208
  fi

  NEW_MAXIMUM_DESIRED=$((EXISTING_MAXIMUM + PROTECTED_INSTANCES_COUNT))
  echo "Creating new Instance Configuration for group $GROUP_NAME based on the existing one"

  echo "Will launch $PROTECTED_INSTANCES_COUNT protected instances (new max $NEW_MAXIMUM_DESIRED) in group $GROUP_NAME"
  instanceGroupLaunchResponse=$(curl -s -w "\n %{http_code}" -X POST \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/actions/launch-protected \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
  "tags": {"release_number": "'$JIBRI_RELEASE_NUMBER'"},
  "instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",
  "count": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '$NEW_MAXIMUM_DESIRED',
  "protectedTTLSec": '$JVB_PROTECTED_TTL_SEC'
}')
  launchGroupHttpCode=$(tail -n1 <<<"$instanceGroupLaunchResponse" | sed 's/[^0-9]*//g')
  if [ "$launchGroupHttpCode" == 200 ]; then
    echo "Successfully launched $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"
  else
    echo "Error launching $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $launchGroupHttpCode"
    exit 208
  fi

  #Wait as much as it will take to provision the new instances, before scaling down the existing ones
  sleep 90

  echo "Will scale down the group $GROUP_NAME and keep only the $PROTECTED_INSTANCES_COUNT protected instances with maximum $EXISTING_MAXIMUM"
  instanceGroupScaleDownResponse=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/desired \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
  "desiredCount": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '"$EXISTING_MAXIMUM"'
}')
  scaleDownGroupHttpCode=$(tail -n1 <<<"$instanceGroupScaleDownResponse" | sed 's/[^0-9]*//g')
  if [ "$scaleDownGroupHttpCode" == 200 ]; then
    echo "Successfully scaled down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"
  else
    echo "Error scaling down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $scaleDownGroupHttpCode"
    exit 209
  fi

else
  echo "No group named $GROUP_NAME was found nor created. AutoScaler response status code is $getGroupHttpCode\n$instanceGroupDetails"
  exit 210
fi
