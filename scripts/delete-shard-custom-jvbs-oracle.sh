#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

if [ -z "$SHARD" ]; then
  echo "No SHARD found.  Exiting..."
  exit 210
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

[ -z "$SHARD_CORE_CLOUD_PROVIDER" ] && SHARD_CORE_CLOUD_PROVIDER="aws"

if [ -z "$ORACLE_REGION" ]; then
  if [[ "$SHARD_CORE_CLOUD_PROVIDER" == "aws" ]]; then
    # Extract EC2_REGION from the shard name and use it to get the ORACLE_REGION
    EC2_REGION=$($LOCAL_PATH/shard.py  --shard_region --environment=$ENVIRONMENT --shard=$SHARD)
    #pull in AWS region-specific variables, including ORACLE_REGION
    [ -e "$LOCAL_PATH/../regions/${EC2_REGION}.sh" ] && . "$LOCAL_PATH/../regions/${EC2_REGION}.sh"
  fi
  if [[ "$SHARD_CORE_CLOUD_PROVIDER" == "oracle" ]]; then
    ORACLE_REGION=$($LOCAL_PATH/shard.py  --shard_region --environment=$ENVIRONMENT --shard=$SHARD --oracle)
  fi
  if [[ "$SHARD_CORE_CLOUD_PROVIDER" == "nomad" ]]; then
    ORACLE_REGION=$($LOCAL_PATH/shard.py  --shard_region --environment=$ENVIRONMENT --shard=$SHARD --oracle)
  fi
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

[ -z "$GROUP_NAME" ] && GROUP_NAME="$SHARD-JVBCustomGroup"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="$SHARD-JVBInstanceConfig"

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
    exit 0
  elif [ "$getGroupHttpCode" == 000 ]; then
    echo "Local autoscaler not present for $GROUP_NAME. Assuming no more work to do"
    exit 0
  elif [ "$getGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was found in the autoscaler"
    export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
  fi
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.cloud")"
fi

export GROUP_NAME
export ORACLE_REGION
export TYPE="JVB"
export TOKEN
export MIN_DESIRED=0
export MAX_DESIRED=0
export DESIRED_COUNT=0


function delGroup() {
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
    return 0
  else
    echo "Failed deleting the group $GROUP_NAME. Returning"
    return 222
  fi  
}



# Scale down JVB custom group to 0
##################################
$LOCAL_PATH/custom-autoscaler-update-desired-values.sh
RESULT=$?

if [ "$RESULT" -eq 0 ]; then
  # Wait a while until the JVBs gracefully terminate
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
    GROUP_REPORT_INSTANCES="$(echo "$GROUP_REPORT_VALUE" | jq '.groupReport.instances | map(select(.cloudStatus!="SHUTDOWN"))')"
    INSTANCES=$(echo "$GROUP_REPORT_INSTANCES" | jq -r '.[].instanceId')
    for INSTANCE_ID in $INSTANCES; do
      if (echo "$INSTANCE_ID" | grep -q "/dispatch-"); then
        echo "Terminating nomad instance $INSTANCE_ID"
        $LOCAL_PATH/nomad.sh job stop $INSTANCE_ID
      else
        echo "Terminating JVB instance $INSTANCE_ID"
        oci --region $ORACLE_REGION compute instance terminate --force --instance-id $INSTANCE_ID
      fi
    done
  else
    echo "Failed to get remaining group report instances. Please retry the script"
    exit 220
  fi

  DELETE_FAILED=true
# by default retry for up to 6 hours 
  DELETE_RETRIES=72 # 12 retries in an hour (every 5 mins), 6 hours
  DELETE_RETRY=0
  while $DELETE_FAILED; do
    delGroup
    if [ $? -eq 0 ]; then
      DELETE_FAILED=false
    else
      DELETE_RETRY=$((DELETE_RETRY+1))
      if [[ $DELETE_RETRY -gt $DELETE_RETRIES ]]; then
        echo "Retries exhausted, failed to delete many times"
        DELETE_FAILED=false
      else
        # failed, but within our retry limit so sleep and try again in 5 mins
        sleep 300
      fi
    fi
  done
elif [ "$RESULT" -eq 230 ]; then
  echo "Group $GROUP_NAME not found, but continuing to check if there are remaining instance configurations to be deleted"
elif [ "$RESULT" -gt 0 ]; then
  echo "Failed setting min=max=desired=0 on the group $GROUP_NAME. Exiting.."
  exit 221
fi

# Delete instance configuration(s) for that shard
##################################
if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
  $LOCAL_PATH/../terraform/create-jvb-instance-configuration/delete-jvb-instance-configuration.sh
fi

if [[ "$CLOUD_PROVIDER" == "nomad" ]]; then
  # find all running jobs matching prefix and stop them
  $LOCAL_PATH/nomad.sh status jvb-$SHARD | grep "dispatch-" | grep -v 'dead' | awk '{print $1}' | xargs -n1 $LOCAL_PATH/nomad.sh job stop
  $LOCAL_PATH/nomad.sh system gc
  sleep 30
  $LOCAL_PATH/nomad-pack.sh stop jitsi_meet_jvb --name jvb-$SHARD
fi

# INSTANCE_CONFIGURATIONS=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard" == `'"$SHARD"'`]' | jq -r .[].id)

# for INSTANCE_CONFIGURATION_ID in $INSTANCE_CONFIGURATIONS; do
#   echo "Deleting instance configuration $INSTANCE_CONFIGURATION_ID"
#   oci compute-management instance-configuration delete --instance-configuration-id "$INSTANCE_CONFIGURATION_ID" --region "$ORACLE_REGION" --force
# done
