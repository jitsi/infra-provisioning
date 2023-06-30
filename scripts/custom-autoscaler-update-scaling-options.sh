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

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

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

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

if [ -z "$TYPE" ]; then
  echo "No TYPE provided or found. Exiting.. "
  exit 213
fi

if [ "$TYPE" == 'jibri' ]; then
  [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="JibriCustomGroup"
  [ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
elif [ "$TYPE" == 'sip-jibri' ]; then
  [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="SipJibriCustomGroup"
  [ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
else
  if [ -z "$GROUP_NAME" ]; then
    echo "No GROUP_NAME provided or found. Exiting.. "
    exit 214
  fi
fi

#allow empty values
[ -z "$SCALE_UP_QUANTITY" ] && SCALE_UP_QUANTITY=
[ -z "$SCALE_DOWN_QUANTITY" ] && SCALE_DOWN_QUANTITY=
[ -z "$SCALE_UP_THRESHOLD" ] && SCALE_UP_THRESHOLD=
[ -z "$SCALE_DOWN_THRESHOLD" ] && SCALE_DOWN_THRESHOLD=
[ -z "$SCALE_PERIOD" ] && SCALE_PERIOD=
[ -z "$SCALE_UP_PERIODS_COUNT" ] && SCALE_UP_PERIODS_COUNT=
[ -z "$SCALE_DOWN_PERIODS_COUNT" ] && SCALE_DOWN_PERIODS_COUNT=

echo "Update scaling options for group $GROUP_NAME"

REQUEST_BODY='{
}'

if [ "$SCALE_UP_QUANTITY" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_UP_QUANTITY "$SCALE_UP_QUANTITY" '. += {"scaleUpQuantity": '$SCALE_UP_QUANTITY'}')
fi

if [ "$SCALE_DOWN_QUANTITY" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_DOWN_QUANTITY "$SCALE_DOWN_QUANTITY" '. += {"scaleDownQuantity": '$SCALE_DOWN_QUANTITY'}')
fi

if [ "$SCALE_UP_THRESHOLD" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_UP_THRESHOLD "$SCALE_UP_THRESHOLD" '. += {"scaleUpThreshold": '$SCALE_UP_THRESHOLD'}')
fi

if [ "$SCALE_DOWN_THRESHOLD" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_DOWN_THRESHOLD "$SCALE_DOWN_THRESHOLD" '. += {"scaleDownThreshold": '$SCALE_DOWN_THRESHOLD'}')
fi

if [ "$SCALE_PERIOD" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg ENABLE_AUTO_SCALE "$SCALE_PERIOD" '. += {"scalePeriod": '$SCALE_PERIOD'}')
fi

if [ "$SCALE_UP_PERIODS_COUNT" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_UP_PERIODS_COUNT "$SCALE_UP_PERIODS_COUNT" '. += {"scaleUpPeriodsCount": '$SCALE_UP_PERIODS_COUNT'}')
fi

if [ "$SCALE_DOWN_PERIODS_COUNT" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg SCALE_DOWN_PERIODS_COUNT "$SCALE_DOWN_PERIODS_COUNT" '. += {"scaleDownPeriodsCount": '$SCALE_DOWN_PERIODS_COUNT'}')
fi

if [ "$GRACE_PERIOD" ]; then
  REQUEST_BODY=$(echo "$REQUEST_BODY" | jq --arg GRACE_PERIOD "$GRACE_PERIOD" '. += {"gracePeriodTTLSec": '$GRACE_PERIOD'}')
fi

response=$(curl -s -w "\n %{http_code}" -X PUT \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/scaling-options \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "$REQUEST_BODY")

updateGroupHttpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g') # get the last line

if [ "$updateGroupHttpCode" == 200 ]; then
  echo "Successfully updated scaling options for group $GROUP_NAME"
else
  echo "Error updating scaling options for group $GROUP_NAME. AutoScaler response status code is $updateGroupHttpCode"
  exit 208
fi
