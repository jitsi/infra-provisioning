#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ENVIRONMENT" ] && echo "ENVIRONMENT is not set" && exit 1
[ -z "$GROUP_NAME" ] && echo "GROUP_NAME is not set" && exit 1
[ -z "$ROTATE_SLEEP_SECONDS" ] && ROTATE_SLEEP_SECONDS=600

set -x

# first launch protected instances in the group
# source in order to properly access the variables
. $LOCAL_PATH/custom-autoscaler-launch-protected.sh

if [[ "$RET" != "0" ]]; then
    echo "Failed to launch protected instances: code $RET"
    exit $RET
fi

if [[ "$SKIP_SCALE_DOWN" != "true" ]]; then
    if [[ "$SKIP_HEALTH_CHECK" == "true" ]]; then
        # now wait until launched instances are ready
        sleep $ROTATE_SLEEP_SECONDS
    else
        # wait until the new instances report healthy application stats via
        # the sidecar before scaling down the old ones; on failure leave the
        # old instances serving and restore the previous instance configuration
        export GROUP_NAME AUTOSCALER_URL TOKEN PRE_ROTATION_INSTANCE_IDS GROUP_TYPE HEALTH_CHECK_TIMEOUT
        EXPECTED_COUNT=$PROTECTED_INSTANCES_COUNT $LOCAL_PATH/check-group-rotation-health.sh
        if [ $? -gt 0 ]; then
            echo "Health check FAILED for new instances in group $GROUP_NAME, skipping scale down; old instances are left running"
            if [ -n "$NEW_INSTANCE_CONFIGURATION_ID" ] && [ "$NEW_INSTANCE_CONFIGURATION_ID" != "$EXISTING_INSTANCE_CONFIGURATION_ID" ]; then
                echo "Restoring previous instance configuration $EXISTING_INSTANCE_CONFIGURATION_ID on group $GROUP_NAME"
                restoreConfigResponse=$(curl -s -w "\n %{http_code}" -X PUT \
                    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/instance-configuration \
                    -H 'Content-Type: application/json' \
                    -H "Authorization: Bearer $TOKEN" \
                    -d '{"instanceConfigurationId": '\""$EXISTING_INSTANCE_CONFIGURATION_ID"'"}')
                restoreConfigHttpCode=$(tail -n1 <<<"$restoreConfigResponse" | sed 's/[^0-9]*//g')
                if [ "$restoreConfigHttpCode" == 200 ]; then
                    echo "Successfully restored previous instance configuration on group $GROUP_NAME"
                else
                    echo "Error restoring previous instance configuration on group $GROUP_NAME. AutoScaler response status code is $restoreConfigHttpCode"
                fi
            fi
            echo "The unhealthy protected instances will lose scale-down protection after $PROTECTED_TTL_SEC seconds and require manual cleanup"
            exit 223
        fi
    fi

    # now scale down to the previous desired value
    if [ -n "$NEW_MAXIMUM_DESIRED" ]; then
        export MAX_DESIRED=$EXISTING_DESIRED
    fi

    export DESIRED_COUNT=$PROTECTED_INSTANCES_COUNT

    $LOCAL_PATH/custom-autoscaler-update-desired-values.sh
    exit $?
else
    echo "Skipping scale down, SKIP_SCALE_DOWN is set to true"
    exit 0
fi
