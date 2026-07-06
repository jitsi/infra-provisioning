#!/bin/bash
# polls the autoscaler group report until at least EXPECTED_COUNT newly-launched
# instances report a healthy application status, i.e. the sidecar is successfully
# polling the local application for stats (scaleStatus SIDECAR_RUNNING or IN USE).
# used by create-or-rotate-custom-jvb-oracle.sh to gate the scale-down of old
# instances on the health of their replacements.
#
# new instances are identified by not appearing in PRE_ROTATION_INSTANCE_IDS
# (space-separated instance ids captured before launch) and, when
# EXPECTED_VERSION is set, by the sidecar-reported application version.

if [ -z "$GROUP_NAME" ]; then
  echo "No GROUP_NAME provided or found. Exiting.. "
  exit 213
fi

if [ -z "$EXPECTED_COUNT" ]; then
  echo "No EXPECTED_COUNT found.  Exiting..."
  exit 220
fi

if [ -z "$TOKEN" ]; then
  if [ -z "$JWT_ENV_FILE" ]; then
    if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
      echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
      exit 211
    fi

    JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
  fi

  TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

# scaleStatus values indicating the application is up and reporting stats
[ -z "$HEALTHY_STATUSES" ] && HEALTHY_STATUSES="SIDECAR_RUNNING,IN USE"

# no version assertion possible when rotating to 'latest'
[ "$EXPECTED_VERSION" == "latest" ] && EXPECTED_VERSION=""

if [ -z "$PRE_ROTATION_INSTANCE_IDS" ] && [ -z "$EXPECTED_VERSION" ]; then
  echo "Neither PRE_ROTATION_INSTANCE_IDS nor EXPECTED_VERSION provided, cannot identify new instances. Exiting.."
  exit 221
fi

[ -z "$HEALTH_CHECK_TIMEOUT" ] && HEALTH_CHECK_TIMEOUT=900
[ -z "$HEALTH_CHECK_INTERVAL" ] && HEALTH_CHECK_INTERVAL=60

WAIT_TOTAL_SECONDS=0
while true; do
  instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/report \
    -H "Authorization: Bearer $TOKEN")

  GROUP_REPORT_STATUS_CODE=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
  GROUP_REPORT_VALUE=$(sed '$ d' <<<"$instanceGroupGetResponse")                           # get all but the last line which contains the status code

  if [ "$GROUP_REPORT_STATUS_CODE" == 200 ]; then
    NEW_INSTANCES=$(echo "$GROUP_REPORT_VALUE" | jq --arg pre "$PRE_ROTATION_INSTANCE_IDS" --arg version "$EXPECTED_VERSION" \
      '[.groupReport.instances[]
        | select((.isShuttingDown != true) and ((.shutdownComplete == null) or (.shutdownComplete == false)))
        | select(.instanceId as $id | ($pre | split(" ")) | index($id) | not)
        | select(($version == "") or (.version == $version))]')
    NEW_COUNT=$(echo "$NEW_INSTANCES" | jq -r 'length')
    HEALTHY_COUNT=$(echo "$NEW_INSTANCES" | jq -r --arg statuses "$HEALTHY_STATUSES" \
      '[.[] | select(.scaleStatus as $s | ($statuses | split(",")) | index($s))] | length')
    [ -z "$HEALTHY_COUNT" ] && HEALTHY_COUNT=0

    if [ "$HEALTHY_COUNT" -ge "$EXPECTED_COUNT" ]; then
      echo "Health check passed for group $GROUP_NAME: $HEALTHY_COUNT healthy new instances of $NEW_COUNT new total, expected $EXPECTED_COUNT"
      exit 0
    fi

    echo "Group $GROUP_NAME has $HEALTHY_COUNT healthy new instances of $NEW_COUNT new total, waiting for $EXPECTED_COUNT"
  else
    echo "Failed to get group $GROUP_NAME report, status is $GROUP_REPORT_STATUS_CODE"
  fi

  if [ $WAIT_TOTAL_SECONDS -lt $HEALTH_CHECK_TIMEOUT ]; then
    echo "Sleeping $HEALTH_CHECK_INTERVAL..."
    sleep $HEALTH_CHECK_INTERVAL
    WAIT_TOTAL_SECONDS=$(( WAIT_TOTAL_SECONDS + HEALTH_CHECK_INTERVAL ))
  else
    echo "Error. Reached maximum wait time of $WAIT_TOTAL_SECONDS seconds with only ${HEALTHY_COUNT:-0} of $EXPECTED_COUNT expected healthy new instances in group $GROUP_NAME"
    if [ -n "$NEW_INSTANCES" ]; then
      echo "Unhealthy new instances in group $GROUP_NAME:"
      echo "$NEW_INSTANCES" | jq --arg statuses "$HEALTHY_STATUSES" \
        '[.[] | select(.scaleStatus as $s | ($statuses | split(",")) | index($s) | not) | {instanceId, displayName, scaleStatus, cloudStatus, version, privateIp}]'
    fi
    exit 210
  fi
done
