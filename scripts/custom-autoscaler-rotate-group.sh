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
    # now wait until launched instances are ready
    sleep $ROTATE_SLEEP_SECONDS

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
