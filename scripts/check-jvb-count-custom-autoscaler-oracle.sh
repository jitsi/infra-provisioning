#!/bin/bash
set -x #echo on

# Input
#############################

if [ -z "$GROUP_NAME" ]; then
  echo "No GROUP_NAME provided or found. Exiting.. "
  exit 213
fi

if [ -z "$EXPECTED_COUNT" ]; then
  echo "No EXPECTED_COUNT found.  Exiting..."
  exit 220
fi

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

[ -z "$CHECK_SCALE_UP" ] && CHECK_SCALE_UP="true"

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)


# by default, wait for maximum 15 min for JVBs to reach the desired count
[ -z "$MAX_WAIT_SECONDS" ] && MAX_WAIT_SECONDS=900
[ -z "$SLEEP_INTRVAL_SECONDS" ] && SLEEP_INTRVAL_SECONDS=60

# Wait group to reach desired
#############################

WAIT_TOTAL_SECONDS=0
while true; do
  instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/report \
    -H "Authorization: Bearer $TOKEN")

  GROUP_REPORT_STATUS_CODE=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
  GROUP_REPORT_VALUE=$(sed '$ d' <<<"$instanceGroupGetResponse")                           # get all but the last line which contains the status code

  if [ "$GROUP_REPORT_STATUS_CODE" == 200 ]; then
    COUNT=$(echo "$GROUP_REPORT_VALUE" | jq -r '.groupReport.count')
    PROVISIONING_COUNT=$(echo "$GROUP_REPORT_VALUE" | jq -r '.groupReport.provisioningCount')
    SHUTTING_DOWN_COUNT=$(echo "$GROUP_REPORT_VALUE" | jq -r '.groupReport.shuttingDownCount')
    SHUTDOWN_COUNT=$(echo "$GROUP_REPORT_VALUE" | jq -r '.groupReport.instances|map(select(.cloudStatus=="SHUTDOWN" or .cloudStatus=="unknown" or .shutdownComplete!=null))|length')
    COUNT_TO_CHECK="$((COUNT - SHUTDOWN_COUNT))"

    if [ "$CHECK_SCALE_UP" == "true" ]; then
      COUNT_TO_CHECK=$(( COUNT - PROVISIONING_COUNT - SHUTTING_DOWN_COUNT - SHUTDOWN_COUNT ))
      if [ "$COUNT_TO_CHECK" -ge "$EXPECTED_COUNT" ]; then
          echo "There are now $COUNT_TO_CHECK instances running in group $GROUP_NAME."
          exit 0
      fi
    elif [ "$COUNT_TO_CHECK" -eq "$EXPECTED_COUNT" ]; then
      echo "There are now $EXPECTED_COUNT total instances in group $GROUP_NAME"
      exit 0
    fi

    echo "Group $GROUP_NAME has expected count $EXPECTED_COUNT and checked count $COUNT_TO_CHECK, after checking with CHECK_SCALE_UP=$CHECK_SCALE_UP"
  else
    echo "Failed to get group $GROUP_NAME report, status is $GROUP_REPORT_STATUS_CODE"
  fi

  # failure to either get report or condition not met
  if [ $WAIT_TOTAL_SECONDS -lt $MAX_WAIT_SECONDS ]; then
    echo "Sleeping $SLEEP_INTRVAL_SECONDS..."
    sleep $SLEEP_INTRVAL_SECONDS
    WAIT_TOTAL_SECONDS=$(( $WAIT_TOTAL_SECONDS + $SLEEP_INTRVAL_SECONDS ))
  else
    echo "Error. Reached maximum wait time of $WAIT_TOTAL_SECONDS seconds. Either could not retrieve the group $GROUP_NAME or the group current count is less than expected count $EXPECTED_COUNT"
    exit 210
  fi
done