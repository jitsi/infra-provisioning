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

[ -z "$JIBRI_TYPE" ] && export JIBRI_TYPE="java-jibri"
if [ "$JIBRI_TYPE" != "java-jibri" ] &&  [ "$JIBRI_TYPE" != "sip-jibri" ]; then
  echo "Unsupported jibri type $JIBRI_TYPE";
  exit 206
fi

if [ -z "$JIBRI_RELEASE_NUMBER" ]; then
    JIBRI_RELEASE_NUMBER=0
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

[ -z "$JIBRI_PROTECTED_TTL_SEC" ] && JIBRI_PROTECTED_TTL_SEC=900

# ensure nomad job is defined

. $LOCAL_PATH/deploy-nomad-jibri.sh

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
    export GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-JibriGroup"
fi

echo "Retrieve instance group details for group $GROUP_NAME"
instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group named $GROUP_NAME was found. Will create one"

  [ -z "$JIBRI_ENABLE_AUTO_SCALE" ] && JIBRI_ENABLE_AUTO_SCALE=true
  [ -z "$JIBRI_ENABLE_LAUNCH" ] && JIBRI_ENABLE_LAUNCH=true
  [ -z "$JIBRI_ENABLE_SCHEDULER" ] && JIBRI_ENABLE_SCHEDULER=true
  [ -z "$JIBRI_ENABLE_RECONFIGURATION" ] && JIBRI_ENABLE_RECONFIGURATION=false
  [ -z "$JIBRI_GRACE_PERIOD_TTL_SEC" ] && JIBRI_GRACE_PERIOD_TTL_SEC=150

  [ -z "$JIBRI_SCALE_PERIOD" ] && JIBRI_SCALE_PERIOD=60
  [ -z "$JIBRI_SCALE_UP_PERIODS_COUNT" ] && JIBRI_SCALE_UP_PERIODS_COUNT=5
  [ -z "$JIBRI_SCALE_DOWN_PERIODS_COUNT" ] && JIBRI_SCALE_DOWN_PERIODS_COUNT=20

  # populate first with environment-based default values
  if [ "$JIBRI_TYPE" == "java-jibri" ]; then
    [ -z "$TYPE" ] && TYPE="jibri"
    [ -z $JIBRI_MAX_COUNT ] && JIBRI_MAX_COUNT=$DEFAULT_JIBRI_MAX_COUNT
    [ -z $JIBRI_MIN_COUNT ] && JIBRI_MIN_COUNT=$DEFAULT_JIBRI_MIN_COUNT
    [ -z $JIBRI_DOWNSCALE_COUNT ] && JIBRI_DOWNSCALE_COUNT=$DEFAULT_JIBRI_DOWNSCALE_COUNT
    [ -z $JIBRI_SCALING_INCREASE_RATE ] && JIBRI_SCALING_INCREASE_RATE=$DEFAULT_JIBRI_SCALING_INCREASE_RATE
    [ -z $JIBRI_SCALING_DECREASE_RATE ] && JIBRI_SCALING_DECREASE_RATE=$DEFAULT_JIBRI_SCALING_DECREASE_RATE
  elif [ "$JIBRI_TYPE" == "sip-jibri" ]; then
    [ -z "$TYPE" ] && TYPE="sip-jibri"
    [ -z $JIBRI_MAX_COUNT ] && JIBRI_MAX_COUNT=$DEFAULT_SIP_JIBRI_MAX_COUNT
    [ -z $JIBRI_MIN_COUNT ] && JIBRI_MIN_COUNT=$DEFAULT_SIP_JIBRI_MIN_COUNT
    [ -z $JIBRI_DOWNSCALE_COUNT ] && JIBRI_DOWNSCALE_COUNT=$DEFAULT_SIP_JIBRI_DOWNSCALE_COUNT
    [ -z $JIBRI_SCALING_INCREASE_RATE ] && JIBRI_SCALING_INCREASE_RATE=$DEFAULT_SIP_JIBRI_SCALING_INCREASE_RATE
    [ -z $JIBRI_SCALING_DECREASE_RATE ] && JIBRI_SCALING_DECREASE_RATE=$DEFAULT_SIP_JIBRI_SCALING_DECREASE_RATE
  fi

  # populate with generic defaults
  [ -z "$JIBRI_MAX_COUNT" ] && JIBRI_MAX_COUNT=20
  [ -z "$JIBRI_MIN_COUNT" ] && JIBRI_MIN_COUNT=2
  [ -z "$JIBRI_DOWNSCALE_COUNT" ] && JIBRI_DOWNSCALE_COUNT=3

  # ensure we don't try to downscale past minimum if minimum is overridden
  if [[ $JIBRI_DOWNSCALE_COUNT -lt $JIBRI_MIN_COUNT ]]; then
    JIBRI_DOWNSCALE_COUNT=$JIBRI_MIN_COUNT
  fi

  [ -z "$JIBRI_DESIRED_COUNT" ] && JIBRI_DESIRED_COUNT=$JIBRI_MIN_COUNT
  [ -z "$JIBRI_AVAILABLE_COUNT" ] && JIBRI_AVAILABLE_COUNT=$JIBRI_DESIRED_COUNT

  # scale up by 1 at a time by default unless overridden
  [ -z "$JIBRI_SCALING_INCREASE_RATE" ] && JIBRI_SCALING_INCREASE_RATE=1
  # scale down by 1 at a time unless overridden
  [ -z "$JIBRI_SCALING_DECREASE_RATE" ] && JIBRI_SCALING_DECREASE_RATE=1

  echo "Creating group named $GROUP_NAME"

  instanceGroupCreateResponse=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
            "name": "'"$GROUP_NAME"'",
            "type": "'$TYPE'",
            "region": "'"$ORACLE_REGION"'",
            "environment": "'"$ENVIRONMENT"'",
            "compartmentId": "'"$COMPARTMENT_OCID"'",
            "instanceConfigurationId": "'"$INSTANCE_CONFIGURATION_ID"'",
            "enableAutoScale": '$JIBRI_ENABLE_AUTO_SCALE',
            "enableLaunch": '$JIBRI_ENABLE_LAUNCH',
            "enableScheduler": '$JIBRI_ENABLE_SCHEDULER',
            "enableReconfiguration": '$JIBRI_ENABLE_RECONFIGURATION',
            "gracePeriodTTLSec": '$JIBRI_GRACE_PERIOD_TTL_SEC',
            "protectedTTLSec": '$JIBRI_PROTECTED_TTL_SEC',
            "scalingOptions": {
                "minDesired": '$JIBRI_MIN_COUNT',
                "maxDesired": '$JIBRI_MAX_COUNT',
                "desiredCount": '$JIBRI_DESIRED_COUNT',
                "scaleUpQuantity": '$JIBRI_SCALING_INCREASE_RATE',
                "scaleDownQuantity": '$JIBRI_SCALING_DECREASE_RATE',
                "scaleUpThreshold": '$JIBRI_AVAILABLE_COUNT',
                "scaleDownThreshold": '$JIBRI_DOWNSCALE_COUNT',
                "scalePeriod": '$JIBRI_SCALE_PERIOD',
                "scaleUpPeriodsCount": '$JIBRI_SCALE_UP_PERIODS_COUNT',
                "scaleDownPeriodsCount": '$JIBRI_SCALE_DOWN_PERIODS_COUNT'
            },
            "tags": {"release_number": "'$JIBRI_RELEASE_NUMBER'"},
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
  "tags": {"release_number": "'$JIBRI_RELEASE_NUMBER'"},
  "instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",
  "count": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '$NEW_MAXIMUM_DESIRED',
  "protectedTTLSec": '$JIBRI_PROTECTED_TTL_SEC'
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
