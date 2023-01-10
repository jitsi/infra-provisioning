#!/bin/bash
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z $SHARD_DATA_PATH ] && SHARD_DATA_PATH=$1

if [ -z $SHARD_DATA_PATH ]; then
    echo "No shard cloudformation templates specified either in command line or in SHARD_DATA_PATH variable"
    exit 10
fi

STACK_IDS=$(cat $SHARD_DATA_PATH | jq -r ".StackId" | cut -d'/' -f2)

if [ -z "$STACK_IDS" ]; then
    echo "No stacks found in cat $SHARD_DATA_PATH | jq -r \".StackId\" | cut -d'/' -f2"
    exit 11
else
    SHARDS=""
    while IFS= read -r line; do
        SHARDS="$line $SHARDS"
    done <<< "$STACK_IDS"
fi

echo "SHARDS=$SHARDS"
echo "HCV_ENVIRONMENT=$ENVIRONMENT"