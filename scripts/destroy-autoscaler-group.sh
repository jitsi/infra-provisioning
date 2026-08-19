#!/bin/bash
set -x #echo on

# Generic, GROUP_NAME-driven autoscaler group teardown.
#
# Unlike the per-type delete scripts (delete-custom-jigasi-pool-oracle.sh,
# delete-custom-jibri-pool-oracle.sh, delete-shard-custom-jvbs-oracle.sh) this
# job does NOT derive the group name from the type. The caller (e.g. Homer's
# Group Management modal) always passes the exact GROUP_NAME, so we operate on
# it directly and discover cloud / region / instance-config id from the
# autoscaler's own group record.
#
# Sequence: scale to 0 -> wait for graceful drain -> force-terminate stragglers
# -> DELETE the group -> delete the group's instance configuration(s).
#
# Idempotent: "group not found" anywhere is treated as success (exit 230) so the
# caller can safely retry.

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

if [ -z "$GROUP_NAME" ]; then
  echo "No GROUP_NAME provided. Exiting..."
  exit 214
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

#pull in cloud-specific variables, e.g. tenancy, TAG_NAMESPACE, COMPARTMENT_OCID
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

# Honor an explicit AUTOSCALER_BACKEND override, else fall back to the
# environment default resolved from stack-env.sh.
if [ -n "$AUTOSCALER_BACKEND" ]; then
  export AUTOSCALER_URL="https://$AUTOSCALER_BACKEND-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME"
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

function findGroup() {
  instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
    -H "Authorization: Bearer $TOKEN")

  getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
  instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code
}

echo "Retrieve instance group details for group $GROUP_NAME"
findGroup
if [ "$getGroupHttpCode" == 404 ] || [ "$getGroupHttpCode" == 000 ]; then
  # Fall back to the per-environment/region local autoscaler. This requires a
  # region; if one wasn't supplied there is nothing more we can try, so treat
  # the group as already gone.
  if [ -z "$ORACLE_REGION" ]; then
    echo "No group $GROUP_NAME found at $AUTOSCALER_URL and no ORACLE_REGION to try a local autoscaler. Assuming no more work to do"
    exit 230
  fi
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
  fi
elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
fi

if [ "$getGroupHttpCode" != 200 ]; then
  echo "Unexpected status $getGroupHttpCode retrieving group $GROUP_NAME. Exiting"
  exit 220
fi

# Discover context from the group record instead of deriving it per-type.
export CLOUD_PROVIDER="$(echo "$instanceGroupDetails" | jq -r '.instanceGroup.cloud')"
INSTANCE_CONFIGURATION_ID="$(echo "$instanceGroupDetails" | jq -r '.instanceGroup.instanceConfigurationId')"
GROUP_REGION="$(echo "$instanceGroupDetails" | jq -r '.instanceGroup.region')"

# Prefer the caller-supplied region, else read it from the group record.
if [ -z "$ORACLE_REGION" ]; then
  if [ -n "$GROUP_REGION" ] && [ "$GROUP_REGION" != "null" ]; then
    ORACLE_REGION="$GROUP_REGION"
  fi
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found (not supplied and not present on the group record). Exiting..."
  exit 203
fi

# Now that the region is known, pull in region-specific cloud variables
# (COMPARTMENT_OCID etc.) used by the instance-configuration cleanup below.
ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh"

# Scale the group down to 0
##################################
export GROUP_NAME
export ORACLE_REGION
export TOKEN
export AUTOSCALER_URL
export MIN_DESIRED=0
export MAX_DESIRED=0
export DESIRED_COUNT=0
"$LOCAL_PATH"/custom-autoscaler-update-desired-values.sh
RESULT=$?

function delGroup() {
  # Delete the group
  ##################################
  echo "Deleting the group $GROUP_NAME"
  groupDeleteResponse=$(curl -s -w "\n %{http_code}" -X DELETE \
        "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
        -H "Authorization: Bearer $TOKEN")

  GROUP_DELETE_STATUS_CODE=$(tail -n1 <<<"$groupDeleteResponse" | sed 's/[^0-9]*//g') # get the last line

  if [ "$GROUP_DELETE_STATUS_CODE" == 200 ] || [ "$GROUP_DELETE_STATUS_CODE" == 404 ]; then
    echo "Group $GROUP_NAME is deleted (status $GROUP_DELETE_STATUS_CODE)"
    return 0
  else
    echo "Failed deleting the group $GROUP_NAME (status $GROUP_DELETE_STATUS_CODE). Returning"
    return 222
  fi
}

if [ "$RESULT" -eq 0 ]; then

  if [[ "$FORCE_IMMEDIATE_DELETE" == "true" ]]; then
    echo "Forcing immediate delete, skipping wait and check"
  else
    # Wait a while until the instances gracefully terminate
    ##################################
    export EXPECTED_COUNT=0
    export CHECK_SCALE_UP="false"
    "$LOCAL_PATH"/check-jvb-count-custom-autoscaler-oracle.sh
  fi

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
      # Termination is the one place we branch on cloud provider. Nomad-dispatched
      # instances carry a "/dispatch-" job id and must be purged via nomad; VM
      # instances (oracle) are terminated directly. For aws we rely on the
      # autoscaler's own termination plus the group DELETE below.
      if (echo "$INSTANCE_ID" | grep -q "/dispatch-"); then
        echo "Terminating nomad instance $INSTANCE_ID"
        ENVIRONMENT="$ENVIRONMENT" "$LOCAL_PATH"/nomad.sh job stop -purge "$INSTANCE_ID"
      elif [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
        echo "Terminating oracle instance $INSTANCE_ID"
        oci --region "$ORACLE_REGION" compute instance terminate --force --instance-id "$INSTANCE_ID"
      else
        echo "Not directly terminating instance $INSTANCE_ID on cloud '$CLOUD_PROVIDER'; relying on autoscaler termination and group delete"
      fi
    done
  else
    echo "Failed to get remaining group report instances. Please retry the script"
    exit 220
  fi

  # Delete the group, retrying on transient failures (deletion can briefly fail
  # while the autoscaler finishes reaping instances).
  ##################################
  DELETE_FAILED=true
  DELETE_RETRIES=180 # every 2 mins, up to ~6 hours
  DELETE_RETRY=0
  while $DELETE_FAILED; do
    delGroup
    if [ $? -eq 0 ]; then
      DELETE_FAILED=false
    else
      DELETE_RETRY=$((DELETE_RETRY+1))
      if [[ $DELETE_RETRY -gt $DELETE_RETRIES ]]; then
        echo "Retries exhausted, failed to delete group $GROUP_NAME"
        exit 222
      else
        sleep 120
      fi
    fi
  done

elif [ "$RESULT" -eq 230 ]; then
  echo "Group $GROUP_NAME not found, but continuing to check if there are remaining instance configurations to be deleted"
elif [ "$RESULT" -gt 0 ]; then
  echo "Failed setting min=max=desired=0 on the group $GROUP_NAME. Exiting.."
  exit 221
fi

# Delete the group's instance configuration(s)
##################################
# Prefer the config the group itself referenced (discovered above) - this keeps
# the job generic and avoids the per-type tag-filter cleanup. Instance
# configurations only exist for oracle VM pools.
if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
  if [ -n "$INSTANCE_CONFIGURATION_ID" ] && [ "$INSTANCE_CONFIGURATION_ID" != "null" ]; then
    echo "Deleting instance configuration $INSTANCE_CONFIGURATION_ID referenced by group $GROUP_NAME"
    oci compute-management instance-configuration delete --instance-configuration-id "$INSTANCE_CONFIGURATION_ID" --region "$ORACLE_REGION" --force
  elif [ -n "$TYPE" ] && [ -n "$COMPARTMENT_OCID" ] && [ -n "$TAG_NAMESPACE" ]; then
    # Fallback only when the group did not expose its instance-config id: match
    # on the shard-role defined tag, using the lower-cased TYPE as the role.
    SHARD_ROLE="$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')"
    echo "Group did not expose an instance configuration id; falling back to tag-filtered cleanup for shard-role '$SHARD_ROLE'"
    INSTANCE_CONFIGURATIONS=$(oci compute-management instance-configuration list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --sort-by TIMECREATED --sort-order DESC --all --query 'data[?"defined-tags".'\"$TAG_NAMESPACE\"'."shard-role" == `'"$SHARD_ROLE"'`]' | jq -r .[].id)
    for IC_ID in $INSTANCE_CONFIGURATIONS; do
      echo "Deleting instance configuration $IC_ID"
      oci compute-management instance-configuration delete --instance-configuration-id "$IC_ID" --region "$ORACLE_REGION" --force
    done
  else
    echo "No instance configuration id on the group and insufficient context for tag-filtered fallback; skipping instance-config cleanup"
  fi
else
  echo "Cloud provider '$CLOUD_PROVIDER' has no oracle instance configuration to delete; skipping instance-config cleanup"
fi

echo "Teardown of group $GROUP_NAME complete"
