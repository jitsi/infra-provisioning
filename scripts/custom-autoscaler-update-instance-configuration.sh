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

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

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
elif [ "$TYPE" == "sip-jibri" ]; then
  [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="SipJibriCustomGroup"
  [ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
else
  if [ -z "$GROUP_NAME" ]; then
    echo "No GROUP_NAME provided or found. Exiting.. "
    exit 215
  fi
fi

if [ -z "$INSTANCE_CONFIGURATION_ID" ]; then
  echo "No INSTANCE_CONFIGURATION_ID provided or found. Exiting.. "
  exit 214
fi

REQUEST_BODY='{
  "instanceConfigurationId": "'$INSTANCE_CONFIGURATION_ID'"
}'

echo "Update instance configuration id for group $GROUP_NAME"
response=$(curl -s -w "\n %{http_code}" -X PUT \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/instance-configuration \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "$REQUEST_BODY")

updateGroupHttpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g') # get the last line

if [ "$updateGroupHttpCode" == 200 ]; then
  echo "Successfully updated instance configuration id for group $GROUP_NAME"
else
  echo "Error updating instance configuration id for group $GROUP_NAME. AutoScaler response status code is $updateGroupHttpCode"
  exit 208
fi
