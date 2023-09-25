#!/bin/bash

if [ ! -z "$DEBUG" ]; then
  set -x
fi

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

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

RELEASE_PARAM=""
if [ -z "$ALL_RELEASES" ]; then
  if [ ! -z "$RELEASE_NUMBER" ]; then
    RELEASE_PARAM="&tag.release_number=$RELEASE_NUMBER"
  fi
fi

[ -z "$GROUP_TYPE" ] && GROUP_TYPE="JVB"

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE="$JWT_ENV_FILE" /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

RESPONSE_BODY=""
RESPONSE_HTTP_CODE=0
function AutoscalerRequest() {
  AUTOSCALER_PATH=$1
  AUTOSCALER_METHOD=$2

  if [ -z "$AUTOSCALER_METHOD" ]; then
    [ -z "$REQUEST_BODY" ] && AUTOSCALER_METHOD="GET"
  else
    AUTOSCALER_METHOD="PUT"
      echo "PUT $AUTOSCALER_URL$AUTOSCALER_PATH with body: $REQUEST_BODY"
  fi

  if [ ! -z "$REQUEST_BODY" ]; then
    BODY="-d $REQUEST_BODY"
  else
    BODY=""
  fi

#  echo "making request: $AUTOSCALER_METHOD to $AUTOSCALER_URL$AUTOSCALER_PATH"
#  echo "using body: $REQUEST_BODY"

  RESPONSE_BODY_AND_STATUS=$(curl -X $AUTOSCALER_METHOD \
    "$AUTOSCALER_URL$AUTOSCALER_PATH" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    $BODY 2>/dev/null)

  if [[ $? -eq 0 ]]; then
      RESPONSE_HTTP_CODE=200
  else
    RESPONSE_HTTP_CODE=500
  fi
  RESPONSE_BODY="$RESPONSE_BODY_AND_STATUS"
#  echo "Received response code: $RESPONSE_HTTP_CODE, body: $RESPONSE_BODY"
  return 0;
}

GET_PATH="/groups"
FULL_SCALING_PATH="/groups/options/full-scaling"


AutoscalerRequest "$GET_PATH?environment=$ENVIRONMENT$RELEASE_PARAM"


if [ "$RESPONSE_HTTP_CODE" == 200 ]; then
    AUTOSCALER_GROUPS_JSON="$RESPONSE_BODY"

    SELECT_QUERY="select(.environment==\"$ENVIRONMENT\")|select(.type==\"$GROUP_TYPE\")"
    if [ ! -z "$ORACLE_REGION" ]; then
      SELECT_QUERY="$SELECT_QUERY|select(.region==\"$ORACLE_REGION\")"
    fi

    if [ ! -z "$GROUP_RECONFIGURATION_ENABLED" ]; then
      SELECT_QUERY="$SELECT_QUERY|select(.enableReconfiguration==$GROUP_RECONFIGURATION_ENABLED)"
    fi

    GROUP_NAMES=$(echo $AUTOSCALER_GROUPS_JSON | jq -r ".instanceGroups[]|$SELECT_QUERY|.name")
    if [ $? -eq 0 ]; then
        echo $GROUP_NAMES
    fi
else
    echo "Error from HTTP REQUEST code: $RESPONSE_HTTP_CODE"
    echo $RESPONSE_BODY
    exit 12
fi