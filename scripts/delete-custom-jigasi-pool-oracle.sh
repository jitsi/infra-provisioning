#!/bin/bash
set -x #echo on

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found.  Exiting..."
  exit 201
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

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

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

if [[ "$JIGASI_TRANSCRIBER_FLAG" == "true" ]]; then
  SUFFIX="TranscriberCustomGroup"
  IC_SUFFIX="TranscriberInstanceConfig"
else
  SUFFIX="JigasiCustomGroup"
  IC_SUFFIX="JigasiInstanceConfig"
fi

[ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$SUFFIX"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="$ENVIRONMENT-$IC_SUFFIX"

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
    export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
  fi
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
fi

# Scale down Jigasi custom group to 0
##################################

export GROUP_NAME
export ORACLE_REGION
export TYPE="jigasi"
export TOKEN
export MIN_DESIRED=0
export MAX_DESIRED=0
export DESIRED_COUNT=0
$LOCAL_PATH/custom-autoscaler-update-desired-values.sh
RESULT=$?

if [ "$RESULT" -eq 0 ]; then

  if [[ "$FORCE_IMMEDIATE_DELETE" == "true" ]]; then
    echo "Forcing immediate delete, skipping wait and check"
  else

    # Wait a while until the instances gracefully terminate
    ##################################
    export EXPECTED_COUNT=0
    export CHECK_SCALE_UP="false"
    $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh

    # Force terminate remaining instances if there are any left
    ##################################
    echo "Force terminating remaining instances on group $GROUP_NAME, if any"
    instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
          "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/report \
          -H "Authorization: Bearer $TOKEN")

    GROUP_REPORT_STATUS_CODE=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
    GROUP_REPORT_VALUE=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

    if [ "$GROUP_REPORT_STATUS_CODE" == 200 ]; then
      INSTANCES=$(echo $GROUP_REPORT_VALUE | jq -r '.groupReport.instances[].instanceId')
      for INSTANCE_ID in $INSTANCES; do
        echo "Terminating Jigasi instance $INSTANCE_ID"
        oci --region $ORACLE_REGION compute instance terminate --force --instance-id $INSTANCE_ID
      done
    else
      echo "Failed to get remaining group report instances. Please retry the script"
      exit 220
    fi
  fi
  # Delete the group
  ##################################

  echo "Deleting the group $GROUP_NAME"
  groupDeleteResponse=$(curl -s -w "\n %{http_code}" -X DELETE \
        "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
        -H "Authorization: Bearer $TOKEN")

  GROUP_REPORT_STATUS_CODE=$(tail -n1 <<<"$groupDeleteResponse" | sed 's/[^0-9]*//g') # get the last line
  GROUP_REPORT_VALUE=$(sed '$ d' <<<"$groupDeleteResponse")                 # get all but the last line which contains the status code

  if [ "$GROUP_REPORT_STATUS_CODE" == 200 ]; then
    echo "Successfully deleted the group $GROUP_NAME"
  else
    echo "Failed deleting the group $GROUP_NAME. Exiting"
    exec 222
  fi

elif [ "$RESULT" -eq 230 ]; then
  echo "Group $GROUP_NAME not found, but continuing to check if there are remaining instance configurations to be deleted"
elif [ "$RESULT" -gt 0 ]; then
  echo "Failed setting min=max=desired=0 on the group $GROUP_NAME. Exiting.."
  exit 221
fi

# Delete instance configuration(s) for that shard
##################################
INSTANCE_CONFIGURATIONS=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `'"jigasi"'`]' | jq -r .[].id)

for INSTANCE_CONFIGURATION_ID in $INSTANCE_CONFIGURATIONS; do
  echo "Deleting instance configuration $INSTANCE_CONFIGURATION_ID"
  oci compute-management instance-configuration delete --instance-configuration-id "$INSTANCE_CONFIGURATION_ID" --region "$ORACLE_REGION" --force
done
