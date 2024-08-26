#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

# use custom backend if provided, otherwise use default URL for environment
if [ -n "$AUTOSCALER_BACKEND" ]; then
  if [[ "$AUTOSCALER_BACKEND" != "prod" ]] && [[ "$AUTOSCALER_BACKEND" != "pilot" ]]; then
    AUTOSCALER_URL="https://$AUTOSCALER_BACKEND-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME"
  fi
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

if [ -z "$TYPE" ]; then
  echo "No TYPE provided or found. Exiting.. "
  exit 213
fi

if [ -z "$GROUP_NAME" ]; then
  echo "No GROUP_NAME provided or found. Exiting.. "
  exit 214
fi

if [ -z "$INSTANCE_CONFIGURATION_ID" ]; then
  echo "No INSTANCE_CONFIGURATION_ID provided or found. Exiting.. "
  exit 215
fi

if [ -z "$ENABLE_AUTO_SCALE" ]; then
  echo "No ENABLE_AUTO_SCALE provided or found. Exiting.. "
  exit 216
fi

if [ -z "$ENABLE_LAUNCH" ]; then
  echo "No ENABLE_LAUNCH provided or found. Exiting.. "
  exit 217
fi

if [ -z "$ENABLE_SCHEDULER" ]; then
  echo "No ENABLE_SCHEDULER provided or found. Exiting.. "
  exit 217
fi

if [ -z "$ENABLE_RECONFIGURATION" ]; then
  echo "No ENABLE_RECONFIGURATION provided or found. Exiting.. "
  exit 217
fi

if [ -z "$GRACE_PERIOD_TTL_SEC" ]; then
  echo "No GRACE_PERIOD_TTL_SEC provided or found. Exiting.. "
  exit 218
fi

if [ -z "$PROTECTED_TTL_SEC" ]; then
  echo "No PROTECTED_TTL_SEC provided or found. Exiting.. "
  exit 219
fi

if [ -z "$MIN_COUNT" ]; then
  echo "No MIN_COUNT provided or found. Exiting.. "
  exit 220
fi

if [ -z "$MAX_COUNT" ]; then
  echo "No MAX_COUNT provided or found. Exiting.. "
  exit 221
fi

if [ -z "$DESIRED_COUNT" ]; then
  echo "No DESIRED_COUNT provided or found. Exiting.. "
  exit 222
fi

if [ -z "$SCALING_INCREASE_RATE" ]; then
  echo "No SCALING_INCREASE_RATE provided or found. Exiting.. "
  exit 223
fi

if [ -z "$SCALING_DECREASE_RATE" ]; then
  echo "No SCALING_DECREASE_RATE provided or found. Exiting.. "
  exit 224
fi

if [ -z "$SCALE_UP_THRESHOLD" ]; then
  echo "No SCALE_UP_THRESHOLD provided or found. Exiting.. "
  exit 225
fi

if [ -z "$SCALE_DOWN_THRESHOLD" ]; then
  echo "No SCALE_DOWN_THRESHOLD provided or found. Exiting.. "
  exit 226
fi

if [ -z "$SCALE_PERIOD" ]; then
  echo "No SCALE_PERIOD provided or found. Exiting.. "
  exit 227
fi

if [ -z "$SCALE_UP_PERIODS_COUNT" ]; then
  echo "No SCALE_UP_PERIODS_COUNT provided or found. Exiting.. "
  exit 228
fi

if [ -z "$SCALE_DOWN_PERIODS_COUNT" ]; then
  echo "No SCALE_DOWN_PERIODS_COUNT provided or found. Exiting.. "
  exit 229
fi

if [ -z "$CLOUD_PROVIDER" ]; then
  echo "No CLOUD_PROVIDER provided or found. Exiting.. "
  exit 230
fi

# use local autoscaler if nomad is the cloud provider
if [[ "$CLOUD_PROVIDER" == "nomad" ]]; then
  export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
fi

instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group named $GROUP_NAME was found. Will create one"
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  EXISTING_MAXIMUM=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.maxDesired")
  EXISTING_MINIMUM=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.minDesired")
  EXISTING_DESIRED=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.desiredCount")
  if [ -n "$EXISTING_MAXIMUM" ]; then 
    echo "Existing maximum: $EXISTING_MAXIMUM"
    MAX_COUNT=$EXISTING_MAXIMUM
  fi

  if [ -n "$EXISTING_MINIMUM" ]; then 
    echo "Existing minimum: $EXISTING_MINIMUM"
    MIN_COUNT=$EXISTING_MINIMUM
  fi

  if [ -n "$EXISTING_DESIRED" ]; then
    echo "Existing desired: $EXISTING_DESIRED"
    DESIRED_COUNT=$EXISTING_DESIRED
  fi
fi

REQUEST_BODY='{
            "name": "'"$GROUP_NAME"'",
            "type": "'$TYPE'",
            "region": "'"$ORACLE_REGION"'",
            "environment": "'"$ENVIRONMENT"'",
            "compartmentId": "'"$COMPARTMENT_OCID"'",
            "instanceConfigurationId": "'"$INSTANCE_CONFIGURATION_ID"'",
            "enableAutoScale": '$ENABLE_AUTO_SCALE',
            "enableLaunch": '$ENABLE_LAUNCH',
            "enableScheduler": '$ENABLE_SCHEDULER',
            "enableReconfiguration": '$ENABLE_RECONFIGURATION',
            "gracePeriodTTLSec": '$GRACE_PERIOD_TTL_SEC',
            "protectedTTLSec": '$PROTECTED_TTL_SEC',
            "scalingOptions": {
                "minDesired": '$MIN_COUNT',
                "maxDesired": '$MAX_COUNT',
                "desiredCount": '$DESIRED_COUNT',
                "scaleUpQuantity": '$SCALING_INCREASE_RATE',
                "scaleDownQuantity": '$SCALING_DECREASE_RATE',
                "scaleUpThreshold": '$SCALE_UP_THRESHOLD',
                "scaleDownThreshold": '$SCALE_DOWN_THRESHOLD',
                "scalePeriod": '$SCALE_PERIOD',
                "scaleUpPeriodsCount": '$SCALE_UP_PERIODS_COUNT',
                "scaleDownPeriodsCount": '$SCALE_DOWN_PERIODS_COUNT'
            },
            "tags":{
              "release_number": "'"$TAG_RELEASE_NUMBER"'"
            },
            "cloud": "'$CLOUD_PROVIDER'"
}'

echo "Creating group named $GROUP_NAME"
instanceGroupCreateResponse=$(curl -s -w "\n %{http_code}" -X PUT \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "$REQUEST_BODY")

createGroupHttpCode=$(tail -n1 <<<"$instanceGroupCreateResponse" | sed 's/[^0-9]*//g')
if [ "$createGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was created successfully"
else
  echo "Error creating group $GROUP_NAME. AutoScaler response status code is $createGroupHttpCode"
  exit 205
fi
