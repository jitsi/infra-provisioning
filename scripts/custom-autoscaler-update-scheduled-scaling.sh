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

if [ -z "$GROUP_NAME" ]; then
  echo "No GROUP_NAME provided or found. Exiting.. "
  exit 214
fi

[ -z "$ACTION" ] && ACTION="put"

# GET the group's current scheduled scaling config, following the same
# local-autoscaler fallback as custom-autoscaler-update-scaling-activities.sh so
# nomad/local-autoscaler JVB groups resolve correctly.
function getScheduledScaling() {
  getResponse=$(curl -s -w "\n %{http_code}" -X GET \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/scheduled-scaling \
    -H "Authorization: Bearer $TOKEN")
  getHttpCode=$(tail -n1 <<<"$getResponse" | sed 's/[^0-9]*//g')
  getBody=$(sed '$ d' <<<"$getResponse")
}

if [ "$ACTION" == "delete" ]; then
  echo "Deleting scheduled scaling config for group $GROUP_NAME"

  response=$(curl -s -w "\n %{http_code}" -X DELETE \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/scheduled-scaling \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')

  if [ "$httpCode" == 200 ]; then
    echo "Successfully deleted scheduled scaling config for group $GROUP_NAME"
  else
    echo "Error deleting scheduled scaling config for group $GROUP_NAME. AutoScaler response status code is $httpCode"
    exit 208
  fi
elif [ "$ACTION" == "put" ]; then
  if [ -z "$SCHEDULED_SCALING_CONFIG" ]; then
    echo "No SCHEDULED_SCALING_CONFIG provided. Exiting.. "
    exit 220
  fi

  # validate JSON
  if ! echo "$SCHEDULED_SCALING_CONFIG" | jq . > /dev/null 2>&1; then
    echo "SCHEDULED_SCALING_CONFIG is not valid JSON. Exiting.. "
    exit 220
  fi

  echo "Updating scheduled scaling config for group $GROUP_NAME"

  response=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/scheduled-scaling \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d "$SCHEDULED_SCALING_CONFIG")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')

  if [ "$httpCode" == 200 ]; then
    echo "Successfully updated scheduled scaling config for group $GROUP_NAME"
  else
    echo "Error updating scheduled scaling config for group $GROUP_NAME. AutoScaler response status code is $httpCode"
    exit 208
  fi
elif [ "$ACTION" == "enable" ] || [ "$ACTION" == "disable" ]; then
  # Flip only the enabled flag on the group's existing (embedded) schedule,
  # preserving its periods/timezone. Used at set-release-ga to turn internal
  # scheduling on for the GA release and off for groups leaving GA, without
  # re-supplying the schedule. enableScheduler is deprecated and left untouched;
  # the autoscaler drops it to false on its own when enabled=true.
  if [ "$ACTION" == "enable" ]; then TARGET_ENABLED=true; else TARGET_ENABLED=false; fi

  getScheduledScaling
  if { [ "$getHttpCode" == 404 ] || [ "$getHttpCode" == 000 ]; } && [ -n "$ENVIRONMENT" ] && [ -n "$ORACLE_REGION" ]; then
    echo "Group $GROUP_NAME not found at $AUTOSCALER_URL. Trying local autoscaler"
    export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
    getScheduledScaling
  fi

  if [ "$getHttpCode" != 200 ]; then
    echo "Error fetching scheduled scaling config for group $GROUP_NAME. AutoScaler response status code is $getHttpCode"
    exit 208
  fi

  CURRENT_CONFIG=$(echo "$getBody" | jq -c '.scheduledScaling // empty' 2>/dev/null)
  if [ -z "$CURRENT_CONFIG" ]; then
    if [ "$ACTION" == "enable" ]; then
      # No embedded schedule (e.g. a legacy group created before schedules were
      # baked in at creation). Nothing to enable; skip rather than fail the release.
      echo "No scheduled scaling config present for group $GROUP_NAME; cannot enable. Skipping."
      exit 231
    else
      echo "No scheduled scaling config present for group $GROUP_NAME; nothing to disable."
      exit 0
    fi
  fi

  NEW_CONFIG=$(echo "$CURRENT_CONFIG" | jq -c --argjson e "$TARGET_ENABLED" '.enabled=$e')

  echo "Setting scheduled scaling enabled=$TARGET_ENABLED for group $GROUP_NAME"
  response=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/scheduled-scaling \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d "$NEW_CONFIG")

  httpCode=$(tail -n1 <<<"$response" | sed 's/[^0-9]*//g')

  if [ "$httpCode" == 200 ]; then
    echo "Successfully set scheduled scaling enabled=$TARGET_ENABLED for group $GROUP_NAME"
  else
    echo "Error updating scheduled scaling config for group $GROUP_NAME. AutoScaler response status code is $httpCode"
    exit 208
  fi
else
  echo "Unknown ACTION '$ACTION'. Must be 'put', 'delete', 'enable', or 'disable'. Exiting.. "
  exit 221
fi
