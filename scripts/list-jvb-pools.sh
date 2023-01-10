#!/bin/bash

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER"
    exit 2;
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# restrict by cloud if set
if [ ! -z "$CLOUD_NAME" ]; then
    . $LOCAL_PATH/../clouds/$CLOUD_NAME.sh
    export ORACLE_REGION
fi

GROUP_NAMES=""
for R in $RELEASE_NUMBER; do
    GROUP_LIST="$(RELEASE_NUMBER=$R $LOCAL_PATH/custom-autoscaler-list-groups.sh)"
    JVB_GROUPS="$( (for G in $GROUP_LIST; do echo $G; done) | grep "\-${R}-JVBCustomGroup")"
    GROUP_NAMES="$(for G in $JVB_GROUPS; do echo ${G%-JVBCustomGroup}; done) $GROUP_NAMES"
done

echo $GROUP_NAMES