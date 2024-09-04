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

if [ -z "$JIGASI_RELEASE_NUMBER" ]; then
    JIGASI_RELEASE_NUMBER=0
fi

[ -z "$TRANSCRIBER_RELEASE_NUMBER" ] && TRANSCRIBER_RELEASE_NUMBER="$JIGASI_RELEASE_NUMBER"

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

[ -z "$TRANSCRIBER_PROTECTED_TTL_SEC" ] && TRANSCRIBER_PROTECTED_TTL_SEC=900

# ensure nomad job is defined

. $LOCAL_PATH/deploy-nomad-transcriber.sh

if [ $? -gt 0 ]; then
    echo "Failed to deploy nomad job, exiting..."
    exit 222
fi

if [ -z "$NOMAD_URL" ] || [ -z "$NOMAD_JOB_NAME" ]; then
    echo "Failed to find NOMAD_URL or NOMAD_JOB_NAME after deploying nomad job"
    exit 223
else
    export INSTANCE_CONFIGURATION_ID="${NOMAD_URL}|${NOMAD_JOB_NAME}"
    export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
    export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-TranscriberGroup"
fi

echo "Retrieve instance group details for group $GROUP_NAME"
instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group named $GROUP_NAME was found. Will create one"

  [ -z "$TRANSCRIBER_ENABLE_AUTO_SCALE" ] && TRANSCRIBER_ENABLE_AUTO_SCALE=true
  [ -z "$TRANSCRIBER_ENABLE_LAUNCH" ] && TRANSCRIBER_ENABLE_LAUNCH=true
  [ -z "$TRANSCRIBER_ENABLE_SCHEDULER" ] && TRANSCRIBER_ENABLE_SCHEDULER=true
  [ -z "$TRANSCRIBER_ENABLE_RECONFIGURATION" ] && TRANSCRIBER_ENABLE_RECONFIGURATION=false
  [ -z "$TRANSCRIBER_GRACE_PERIOD_TTL_SEC" ] && TRANSCRIBER_GRACE_PERIOD_TTL_SEC=150

  [ -z "$TRANSCRIBER_SCALE_PERIOD" ] && TRANSCRIBER_SCALE_PERIOD=60
  [ -z "$TRANSCRIBER_SCALE_UP_PERIODS_COUNT" ] && TRANSCRIBER_SCALE_UP_PERIODS_COUNT=5
  [ -z "$TRANSCRIBER_SCALE_DOWN_PERIODS_COUNT" ] && TRANSCRIBER_SCALE_DOWN_PERIODS_COUNT=20

    [ -z $TRANSCRIBER_MAX_COUNT ] && TRANSCRIBER_MAX_COUNT=$DEFAULT_TRANSCRIBER_MAX_COUNT
    [ -z $TRANSCRIBER_MIN_COUNT ] && TRANSCRIBER_MIN_COUNT=$DEFAULT_TRANSCRIBER_MIN_COUNT
    [ -z $TRANSCRIBER_DOWNSCALE_COUNT ] && TRANSCRIBER_DOWNSCALE_COUNT=$DEFAULT_TRANSCRIBER_DOWNSCALE_COUNT
    [ -z $TRANSCRIBER_SCALING_INCREASE_RATE ] && TRANSCRIBER_SCALING_INCREASE_RATE=$DEFAULT_TRANSCRIBER_SCALING_INCREASE_RATE
    [ -z $TRANSCRIBER_SCALING_DECREASE_RATE ] && TRANSCRIBER_SCALING_DECREASE_RATE=$DEFAULT_TRANSCRIBER_SCALING_DECREASE_RATE


  # populate with generic defaults
  [ -z "$TRANSCRIBER_MAX_COUNT" ] && TRANSCRIBER_MAX_COUNT=20
  [ -z "$TRANSCRIBER_MIN_COUNT" ] && TRANSCRIBER_MIN_COUNT=2
  [ -z "$TRANSCRIBER_DOWNSCALE_COUNT" ] && TRANSCRIBER_DOWNSCALE_COUNT=1

  # ensure we don't try to downscale past minimum if minimum is overridden
  if [[ $TRANSCRIBER_DOWNSCALE_COUNT -lt $TRANSCRIBER_MIN_COUNT ]]; then
    TRANSCRIBER_DOWNSCALE_COUNT=$TRANSCRIBER_MIN_COUNT
  fi

  [ -z "$TRANSCRIBER_DESIRED_COUNT" ] && TRANSCRIBER_DESIRED_COUNT=$TRANSCRIBER_MIN_COUNT
  [ -z "$TRANSCRIBER_AVAILABLE_COUNT" ] && TRANSCRIBER_AVAILABLE_COUNT=$TRANSCRIBER_DESIRED_COUNT

  # scale up by 1 at a time by default unless overridden
  [ -z "$TRANSCRIBER_SCALING_INCREASE_RATE" ] && TRANSCRIBER_SCALING_INCREASE_RATE=1
  # scale down by 1 at a time unless overridden
  [ -z "$TRANSCRIBER_SCALING_DECREASE_RATE" ] && TRANSCRIBER_SCALING_DECREASE_RATE=1

  echo "Creating group named $GROUP_NAME"

  instanceGroupCreateResponse=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
            "name": "'"$GROUP_NAME"'",
            "type": "jigasi",
            "region": "'"$ORACLE_REGION"'",
            "environment": "'"$ENVIRONMENT"'",
            "compartmentId": "'"$COMPARTMENT_OCID"'",
            "instanceConfigurationId": "'"$INSTANCE_CONFIGURATION_ID"'",
            "enableAutoScale": '$TRANSCRIBER_ENABLE_AUTO_SCALE',
            "enableLaunch": '$TRANSCRIBER_ENABLE_LAUNCH',
            "enableScheduler": '$TRANSCRIBER_ENABLE_SCHEDULER',
            "enableReconfiguration": '$TRANSCRIBER_ENABLE_RECONFIGURATION',
            "gracePeriodTTLSec": '$TRANSCRIBER_GRACE_PERIOD_TTL_SEC',
            "protectedTTLSec": '$TRANSCRIBER_PROTECTED_TTL_SEC',
            "scalingOptions": {
                "minDesired": '$TRANSCRIBER_MIN_COUNT',
                "maxDesired": '$TRANSCRIBER_MAX_COUNT',
                "desiredCount": '$TRANSCRIBER_DESIRED_COUNT',
                "scaleUpQuantity": '$TRANSCRIBER_SCALING_INCREASE_RATE',
                "scaleDownQuantity": '$TRANSCRIBER_SCALING_DECREASE_RATE',
                "scaleUpThreshold": '$TRANSCRIBER_AVAILABLE_COUNT',
                "scaleDownThreshold": '$TRANSCRIBER_DOWNSCALE_COUNT',
                "scalePeriod": '$TRANSCRIBER_SCALE_PERIOD',
                "scaleUpPeriodsCount": '$TRANSCRIBER_SCALE_UP_PERIODS_COUNT',
                "scaleDownPeriodsCount": '$TRANSCRIBER_SCALE_DOWN_PERIODS_COUNT'
            },
            "tags": {"release_number": "'$TRANSCRIBER_RELEASE_NUMBER'"},
            "cloud": "'$CLOUD_PROVIDER'"
}')
  createGroupHttpCode=$(tail -n1 <<<"$instanceGroupCreateResponse" | sed 's/[^0-9]*//g')
  if [ "$createGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was created successfully"
  else
    echo "Error creating group $GROUP_NAME. AutoScaler response status code is $createGroupHttpCode"
    exit 205
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
  "tags": {"release_number": "'$TRANSCRIBER_RELEASE_NUMBER'"},
  "instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",
  "count": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '$NEW_MAXIMUM_DESIRED',
  "protectedTTLSec": '$TRANSCRIBER_PROTECTED_TTL_SEC'
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
