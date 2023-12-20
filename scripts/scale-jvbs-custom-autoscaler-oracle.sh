#!/bin/bash
set -x
set -e

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found.  Exiting..."
  exit 201
fi

if [ -z "$SHARD" ]; then
  echo "No SHARD found.  Exiting..."
  exit 210
fi

if [ -z "$DESIRED_COUNT" ]; then
  echo "No DESIRED_COUNT found.  Exiting..."
  exit 220
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

if [ -z "$ORACLE_REGION" ]; then
  # Extract EC2_REGION from the shard name and use it to get the ORACLE_REGION
  EC2_REGION=$($LOCAL_PATH/shard.py --shard_region --environment=$ENVIRONMENT --shard=$SHARD)
  #pull in AWS region-specific variables, including ORACLE_REGION
  [ -e "$LOCAL_PATH/../regions/${EC2_REGION}.sh" ] && . "$LOCAL_PATH/../regions/${EC2_REGION}.sh"
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

[ -z "$GROUP_NAME" ] && GROUP_NAME="$SHARD-JVBCustomGroup"

[ -z "$WAIT_FOR_POSTINSTALL" ] && WAIT_FOR_POSTINSTALL="TRUE"
[ -z "$SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS" ] && SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS=480 # 8 minutes

echo "Running with parameters..."
echo "ENVIRONMENT=$ENVIRONMENT"
echo "SHARD=$SHARD"
echo "DESIRED_COUNT=$DESIRED_COUNT"
echo "ORACLE_REGION=$ORACLE_REGION"

function findGroup() {
  instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
    -H "Authorization: Bearer $TOKEN")

  getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
  instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code
}

echo "Retrieve instance group details for group $GROUP_NAME"
findGroup
if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group $GROUP_NAME found at $AUTOSCALER_URL. Trying local autoscaler"
  export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
  findGroup
  if [ "$getGroupHttpCode" == 404 ]; then
    echo "No group $GROUP_NAME found at $AUTOSCALER_URL. Assuming no more work to do"
    exit 230
  elif [ "$getGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was found in the autoscaler"
    export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
  fi
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
fi

## Scale up (down is not allowed for now)
##########################################
#
## Read the existing group size

instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME"\
  -H "Authorization: Bearer $TOKEN")

GET_GROUP_STATUS_CODE=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
GROUP_DETAILS=$(sed '$ d' <<<"$instanceGroupGetResponse")                           # get all but the last line which contains the status code

if [ "$GET_GROUP_STATUS_CODE" == 200 ]; then
  EXISTING_INSTANCE_GROUP_SIZE=$(echo "$GROUP_DETAILS" | jq -r '.instanceGroup.scalingOptions.desiredCount')
  echo "Retrieved existing instance group size $EXISTING_INSTANCE_GROUP_SIZE"
else
  echo "Failed to get group report $CUSTOM_GROUP_NAME, status is $GET_GROUP_STATUS_CODE"
  exit 211
fi

if [ "$DESIRED_COUNT" -lt "$EXISTING_INSTANCE_GROUP_SIZE" ]; then
  echo "Cannot scale. The current initial capacity, $EXISTING_INSTANCE_GROUP_SIZE, is lower or equal than the requested size, $DESIRED_COUNT"
  exit 226
fi

if [ "$DESIRED_COUNT" -gt "$EXISTING_INSTANCE_GROUP_SIZE" ]; then
  echo "Scaling to $DESIRED_COUNT..."

  export ORACLE_REGION
  export TYPE="JVB"
  export DESIRED_COUNT
  export MIN_DESIRED
  export GROUP_NAME

  $LOCAL_PATH/custom-autoscaler-update-desired-values.sh

  UPDATE_DESIRED_VALUES_RESULT="$?"
  if [ $UPDATE_DESIRED_VALUES_RESULT -gt 0 ]; then
  echo "Failed to update desired values for group $GROUP_NAME. Exiting."
  exit 213
fi
else
  echo "No change in the group size. Nothing to be done."
fi

if [ $WAIT_FOR_POSTINSTALL == "TRUE" ]; then
  echo "Wait for JVB instances to launch"

  if [ $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS -gt 0 ]; then
    echo "Sleeping for $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS seconds before checking postinstall result"
    sleep $SLEEP_SECONDS_BEFORE_POSTINSTALL_CHECKS
  fi

  EXISTING_GROUP_MIN_DESIRED=$(echo "$GROUP_DETAILS" | jq -r '.instanceGroup.scalingOptions.minDesired')
  EXISTING_GROUP_SCALE_DOWN_QUANTITY=$(echo "$GROUP_DETAILS" | jq -r '.instanceGroup.scalingOptions.scaleDownQuantity')

  # While we wait, it is possible that the group will scale down, but only for a few times (as one scale down happens ~ every 10 min)
  EXPECTED_COUNT=$(( $DESIRED_COUNT -  3 * EXISTING_GROUP_SCALE_DOWN_QUANTITY ))
  if [ "$EXPECTED_COUNT" -lt "$EXISTING_GROUP_MIN_DESIRED" ]; then
    EXPECTED_COUNT="$EXISTING_GROUP_MIN_DESIRED"
  fi

  echo "Checking postinstall result and waiting for it to complete..."
  export GROUP_NAME
  export SIDECAR_ENV_VARIABLES
  export AUTOSCALER_URL
  export TOKEN
  export EXPECTED_COUNT
  export CHECK_SCALE_UP="true"
  $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh
  exit $?
fi
