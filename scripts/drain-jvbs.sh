#!/bin/bash

[ -z "$1" ] && SSH_USER=$(whoami) || SSH_USER=$1

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting..."
    exit 1    
fi

[ -z "$DRAIN_ENABLED" ] && DRAIN_ENABLED="true"

echo "SSH_USER=$SSH_USER"

if [ -n "$RELEASE_NUMBER" ]; then
    RELEASE_PARAM=" --release $RELEASE_NUMBER"
fi

DRAIN_URL="http://localhost:8080/colibri/drain"

INVENTORY_FILE="jvb.inventory"
echo "building inventory file $INVENTORY_FILE"
scripts/node.py --environment $ENVIRONMENT --role JVB --batch --oracle --oracle_only --region all $RELEASE_PARAM > $INVENTORY_FILE

echo "Beginning batch operation"
for i in $(cat $INVENTORY_FILE); do
    if [ -n "$SKIP_BRIDGE_IP" ]; then
        if [ "$i" == "$SKIP_BRIDGE_IP" ]; then
            echo "Skipping $i"
            continue
        fi
    fi
    if [[ "$DRAIN_ENABLED" == "true" ]]; then
        echo "Draining $i"
        ssh $SSH_USER@$i "curl -s -X POST $DRAIN_URL/enable -d \"\""
    else
        echo "Readying $i"
        ssh $SSH_USER@$i "curl -s -X POST $DRAIN_URL/disable -d \"\""
    fi
done