#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# default to moving 30% of the endpoints
[ -z "$MOVE_FRACTION" ] && MOVE_FRACTION="0.3"
[ -z "$MOVE_MAX_ENDPOINTS" ] && MOVE_MAX_ENDPOINTS="100"

# check for ENVIRONMENT or exit
if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

. $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

set -x

[ -z "$SSH_USER" ] && SSH_USER="$1"
[ -z "$SSH_USER" ] && SSH_USER="$(whoami)"

# check for JVB_NAME or exit, should look like "prod-8x8-jvb-61-116-158"
if [ -z "$JVB_NAME" ]; then
  echo "No JVB_NAME found. Exiting..."
  exit 203
fi

# JVB identifier in jicofo
MUC_BRIDGE="jvbbrewery@muc.jvb.$DOMAIN/$JVB_NAME"

if [ -z "$JVB_IP" ]; then
    echo "No JVB_IP found. Figuring it out..."
    JVB_IP="$(echo "10."$(echo $JVB_NAME | sed -e "s/${ENVIRONMENT}-jvb-//g" | tr '-' '.'))"
fi

# check for JVB_GROUP_NAME or look it up
if [ -z "$JVB_GROUP_NAME" ]; then
    echo "No JVB_GROUP_NAME found. Looking it up..."
    JVB_GROUP_NAME="$(ssh $SSH_USER@$JVB_IP "cat /tmp/oracle_cache-* | jq -r '.group'")"
fi

if [ -z "$JVB_POOL_MODE" ]; then
    echo "No JVB_POOL_MODE found. Looking it up..."
    JVB_POOL_MODE="$(ssh $SSH_USER@$JVB_IP "cat /tmp/oracle_cache-* | jq -r '.jvb_pool_mode'")"
fi

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER found. Looking it up..."
    RELEASE_NUMBER="$(ssh $SSH_USER@$JVB_IP "cat /tmp/oracle_cache-* | jq -r '.release_number'")"
fi


if [ -z "$ORACLE_REGION" ]; then
    ORACLE_REGION="$(ssh $SSH_USER@$JVB_IP "curl http://169.254.169.254/opc/v1/instance/ | jq -r '.regionInfo.regionIdentifier'")"
fi

# start with local shards

if [[ "$JVB_POOL_MODE" == "remote" ]]; then
    # look up all shards in the release, excluding those in the current region
    SHARD_IPS="$($LOCAL_PATH/node.py --role core --region $ORACLE_REGION --inverse_region --environment $ENVIRONMENT --release $RELEASE_NUMBER --batch --oracle --oracle_only)"
elif [[ "$JVB_POOL_MODE" == "local" ]]; then
    # look up all shards in the release only in the current region
    SHARD_IPS="$($LOCAL_PATH/node.py --role core --region $ORACLE_REGION --environment $ENVIRONMENT --release $RELEASE_NUMBER --batch --oracle --oracle_only)"
else
    # look up all shards in the release in the current region, then the rest
    LOCAL_IPS="$($LOCAL_PATH/node.py --role core --region $ORACLE_REGION --environment $ENVIRONMENT --release $RELEASE_NUMBER --batch --oracle --oracle_only)"
    REMOTE_IPS="$($LOCAL_PATH/node.py --role core --region $ORACLE_REGION --inverse_region --environment $ENVIRONMENT --release $RELEASE_NUMBER --batch --oracle --oracle_only)"
    SHARD_IPS="$LOCAL_IPS $REMOTE_IPS"
fi

TOTAL_MOVED_ENDPOINTS=0
for SHARD_IP in $SHARD_IPS; do
    # looks like '{"movedEndpoints":6,"conferences":1}'
    echo "Attempting to move endpoints on shard $SHARD_IP"
    SHARD_CMD="curl \"0:8888/move-endpoints/move-fraction?bridge=$MUC_BRIDGE&fraction=$MOVE_FRACTION\""
    MOVE_RESPONSE="$(ssh $SSH_USER@$SHARD_IP "$SHARD_CMD")"
    MOVED_ENDPOINTS="$(echo $MOVE_RESPONSE | jq -r '.movedEndpoints')"
    echo "Moved $MOVED_ENDPOINTS endpoints on shard $SHARD_IP"
    TOTAL_MOVED_ENDPOINTS=$((TOTAL_MOVED_ENDPOINTS + MOVED_ENDPOINTS))
    # check if we've moved enough endpoints
    if [ $TOTAL_MOVED_ENDPOINTS -gt $MOVE_MAX_ENDPOINTS ]; then
        echo "Moved $TOTAL_MOVED_ENDPOINTS endpoints, stopping."
        exit 0
    fi
done

echo "Moved $TOTAL_MOVED_ENDPOINTS endpoints, no more shards found."
exit 0