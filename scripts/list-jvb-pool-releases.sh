#!/bin/bash

# Lists the release numbers that still have a JVB pool in the autoscaler,
# whether or not any shard for that release survives. Pool groups are named
# <shard base>-<region>-<pool mode>-<release>-JVBCustomGroup.

if [ -z "$ENVIRONMENT" ]; then
    >&2 echo "No ENVIRONMENT found. Exiting..."
    exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

# custom-autoscaler-list-groups.sh treats a rejected request like an empty
# autoscaler, so without a token it reports no groups rather than failing.
# Mint the token here, where a failure can be told apart from "no pools".
if [ -z "$TOKEN" ]; then
    [ -z "$JWT_ENV_FILE" ] && JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
    TOKEN=$(JWT_ENV_FILE="$JWT_ENV_FILE" /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)
    if [ $? -ne 0 ] || [ -z "$TOKEN" ]; then
        >&2 echo "Could not generate an autoscaler token from $JWT_ENV_FILE. Exiting..."
        exit 1
    fi
fi
export TOKEN

GROUP_LIST="$(RELEASE_NUMBER= $LOCAL_PATH/custom-autoscaler-list-groups.sh)"
if [ $? -ne 0 ]; then
    >&2 echo "Failed to list autoscaler groups: $GROUP_LIST"
    exit 1
fi

RELEASES="$( (for G in $GROUP_LIST; do echo $G; done) | sed -nE 's/.*-([0-9]+)-JVBCustomGroup$/\1/p' | sort -un)"

echo $RELEASES
