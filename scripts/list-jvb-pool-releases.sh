#!/bin/bash

# Lists the release numbers that still have a JVB pool in the autoscaler,
# whether or not any shard for that release survives. Pool groups are named
# <shard base>-<region>-<pool mode>-<release>-JVBCustomGroup.

if [ -z "$ENVIRONMENT" ]; then
    >&2 echo "No ENVIRONMENT found. Exiting..."
    exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

GROUP_LIST="$(RELEASE_NUMBER= $LOCAL_PATH/custom-autoscaler-list-groups.sh)"
if [ $? -ne 0 ]; then
    >&2 echo "Failed to list autoscaler groups: $GROUP_LIST"
    exit 1
fi

RELEASES="$( (for G in $GROUP_LIST; do echo $G; done) | sed -nE 's/.*-([0-9]+)-JVBCustomGroup$/\1/p' | sort -un)"

echo $RELEASES
