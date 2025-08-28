#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#load region defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

if [ -z "${SHARDS_READY}${SHARDS_DRAIN}" ]; then
    echo "Need to define SHARDS_READY and/or SHARDS_DRAIN"
    exit 1
fi

RET=0

function consul_shard_state() {
    S=$1
    STATE=$2
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $S --environment $ENVIRONMENT)

    CONSUL_URL="https://$ENVIRONMENT-$SHARD_REGION-consul.$TOP_LEVEL_DNS_ZONE_NAME/v1/kv/shard-states/$ENVIRONMENT/$SHARD"
    curl -X PUT -d "$STATE" $CONSUL_URL
    return $?
}

for SHARD in $SHARDS_READY; do
    consul_shard_state $SHARD 'ready'
    SRET=$?
    if [[ $SRET -gt 0 ]]; then
        RET=$SRET
    fi
done

for SHARD in $SHARDS_DRAIN; do
    consul_shard_state $SHARD 'drain'
    SRET=$?
    if [[ $SRET -gt 0 ]]; then
        RET=$SRET
    fi
done
exit $RET
