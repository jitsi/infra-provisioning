#!/bin/bash
set -x #echo on

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found.  Exiting..."
  exit 201
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi

if [ -z "$GRID_NAME" ]; then
  echo "No GRID_NAME found.  Exiting..."
  exit 1
fi

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

[ -z "$AUTOSCALER_URL" ] && AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"

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

GROUP_SUFFIXES=("SeleniumGridX86CustomGroup" "SeleniumGridArmCustomGroup")

for SUFFIX in "${GROUP_SUFFIXES[@]}"; do
  GROUP_NAME="${ENVIRONMENT}-${ORACLE_REGION}-${GRID_NAME}-${SUFFIX}"

  function findGroup() {
    instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
      "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
      -H "Authorization: Bearer $TOKEN")

    getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g')
    instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")
  }

  echo "Retrieve instance group details for group $GROUP_NAME"
  findGroup
  if [ "$getGroupHttpCode" == 404 ]; then
    echo "No group $GROUP_NAME found at $AUTOSCALER_URL. Trying local autoscaler"
    ORIG_AUTOSCALER_URL="$AUTOSCALER_URL"
    export AUTOSCALER_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.${TOP_LEVEL_DNS_ZONE_NAME}"
    findGroup
    if [ "$getGroupHttpCode" == 404 ]; then
      echo "No group $GROUP_NAME found at $AUTOSCALER_URL. Skipping"
      export AUTOSCALER_URL="$ORIG_AUTOSCALER_URL"
      continue
    elif [ "$getGroupHttpCode" == 000 ]; then
      echo "Local autoscaler not present for $GROUP_NAME. Skipping"
      export AUTOSCALER_URL="$ORIG_AUTOSCALER_URL"
      continue
    fi
  fi

  if [ "$getGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was found in the autoscaler"

    # Scale down to 0
    export TYPE="selenium-grid"
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
        export EXPECTED_COUNT=0
        export CHECK_SCALE_UP="false"
        $LOCAL_PATH/check-jvb-count-custom-autoscaler-oracle.sh

        # Force terminate remaining instances if there are any left
        echo "Force terminating remaining instances on group $GROUP_NAME, if any"
        instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
              "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/report \
              -H "Authorization: Bearer $TOKEN")

        GROUP_REPORT_STATUS_CODE=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g')
        GROUP_REPORT_VALUE=$(sed '$ d' <<<"$instanceGroupGetResponse")

        if [ "$GROUP_REPORT_STATUS_CODE" == 200 ]; then
          INSTANCES=$(echo $GROUP_REPORT_VALUE | jq -r '.groupReport.instances[].instanceId')
          for INSTANCE_ID in $INSTANCES; do
            echo "Terminating selenium grid instance $INSTANCE_ID"
            oci --region $ORACLE_REGION compute instance terminate --force --instance-id $INSTANCE_ID
          done
        else
          echo "Failed to get remaining group report instances for $GROUP_NAME"
        fi
      fi

      # Delete the group
      echo "Deleting the group $GROUP_NAME"
      groupDeleteResponse=$(curl -s -w "\n %{http_code}" -X DELETE \
            "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
            -H "Authorization: Bearer $TOKEN")

      GROUP_DELETE_STATUS_CODE=$(tail -n1 <<<"$groupDeleteResponse" | sed 's/[^0-9]*//g')

      if [ "$GROUP_DELETE_STATUS_CODE" == 200 ]; then
        echo "Successfully deleted the group $GROUP_NAME"
      else
        echo "Failed deleting the group $GROUP_NAME"
      fi

    elif [ "$RESULT" -eq 230 ]; then
      echo "Group $GROUP_NAME not found during scale down, continuing"
    else
      echo "Failed setting min=max=desired=0 on the group $GROUP_NAME"
    fi
  fi
done
