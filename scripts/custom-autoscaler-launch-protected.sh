#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  RET=203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

if [ -z "$GROUP_NAME" ]; then
    echo "No GROUP_NAME provided or found. Exiting.. "
    RET=214
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  RET=203
fi

[ -z "$PROTECTED_TTL_SEC" ] && PROTECTED_TTL_SEC=900

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    RET=211
    return
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)


if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

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
  elif [ "$getGroupHttpCode" == 000 ]; then
    echo "Local autoscaler not present for $GROUP_NAME. Assuming no more work to do"
    exit 230
  elif [ "$getGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was found in the autoscaler"
    INSTANCE_GROUP_DETAILS=$instanceGroupDetails
  fi
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  INSTANCE_GROUP_DETAILS=$instanceGroupDetails
fi

export EXISTING_MAXIMUM=$(echo "$INSTANCE_GROUP_DETAILS" | jq -r ."instanceGroup.scalingOptions.maxDesired")
export EXISTING_DESIRED=$(echo "$INSTANCE_GROUP_DETAILS" | jq -r ."instanceGroup.scalingOptions.desiredCount")
[ -z "$PROTECTED_INSTANCES_COUNT" ] && export PROTECTED_INSTANCES_COUNT=$EXISTING_DESIRED
if [ -z "$PROTECTED_INSTANCES_COUNT" ]; then
    echo "Something went wrong, could not extract PROTECTED_INSTANCES_COUNT from instanceGroup.scalingOptions.desiredCount";
    exit 208
fi

EXPECTED_COUNT=$((PROTECTED_INSTANCES_COUNT + EXISTING_DESIRED))

if [[ $EXPECTED_COUNT -gt $EXISTING_MAXIMUM ]]; then
    export NEW_MAXIMUM_DESIRED=$((EXISTING_MAXIMUM + PROTECTED_INSTANCES_COUNT))
else
    export NEW_MAXIMUM_DESIRED=
fi

BODY="{"
if [ -n "$NEW_INSTANCE_CONFIGURATION_ID" ]; then
    BODY=$BODY'"instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",'
fi
if [ -n "$NEW_MAXIMUM_DESIRED" ]; then
    BODY=$BODY'"maxDesired": '$NEW_MAXIMUM_DESIRED','
fi
BODY=$BODY'"count": '"$PROTECTED_INSTANCES_COUNT"',"protectedTTLSec": '$PROTECTED_TTL_SEC'}'

echo "Will launch $PROTECTED_INSTANCES_COUNT protected instances (new max $NEW_MAXIMUM_DESIRED) in group $GROUP_NAME: $BODY"
instanceGroupLaunchResponse=$(curl -s -w "\n %{http_code}" -X POST \
"$AUTOSCALER_URL"/groups/"$GROUP_NAME"/actions/launch-protected \
-H 'Content-Type: application/json' \
-H "Authorization: Bearer $TOKEN" \
-d "$BODY")
launchGroupHttpCode=$(tail -n1 <<<"$instanceGroupLaunchResponse" | sed 's/[^0-9]*//g')
if [ "$launchGroupHttpCode" == 200 ]; then
    echo "Successfully launched $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"
    RET=0
else
    echo "Error launching $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $launchGroupHttpCode"
    RET=208
fi
