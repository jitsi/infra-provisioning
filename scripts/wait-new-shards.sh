#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
source $LOCAL_PATH/../clouds/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
source $LOCAL_PATH/../clouds/$CLOUD_NAME.sh

[ -z $SHARD_DATA_PATH ] && SHARD_DATA_PATH=$1

if [ -z $SHARD_DATA_PATH ]; then
    echo "No shard cloudformation templates specified either in command line or in SHARD_DATA_PATH variable"
    exit 10
fi

SHARD_IDS=$(cat $SHARD_DATA_PATH | jq -r ".StackId")

if [ -z "$SHARD_IDS" ]; then
    echo "No shard ids found in cat $SHARD_DATA_PATH | jq -r \".StackId\""
    exit 11
fi
#optimistic
FINAL_RETURN=0

#wait a bit
WAIT_INTERVAL=60

WAIT_FLAG=true
while $WAIT_FLAG; do
    WAIT_FLAG=false
    for SHARD in $SHARD_IDS; do
        SHARD_STATE=$(aws cloudformation describe-stacks --region="$EC2_REGION" --stack-name="$SHARD" | jq -r ".Stacks[0].StackStatus")
        if [ "x$SHARD_STATE" == "xCREATE_COMPLETE" ]; then
            #success
            #don't set the flag, so that we can exit
            #now check the next one
            echo "$SHARD: $SHARD_STATE"
        elif [ "x$SHARD_STATE" == "xCREATE_IN_PROGRESS" ]; then
            #keep waiting
            echo "$SHARD: $SHARD_STATE"
            WAIT_FLAG=true
        elif [ "x$SHARD_STATE" == "xROLLBACK_IN_PROGRESS" ]; then
            #failure of a sort
            echo "$SHARD: $SHARD_STATE"
            FINAL_RETURN=1
            WAIT_FLAG=false
            #don't set the flag, so that we can exit

        elif [ "x$SHARD_STATE" == "xROLLBACK_COMPLETE" ]; then
            #failure of a sort
            echo "$SHARD: $SHARD_STATE"
            FINAL_RETURN=2
            WAIT_FLAG=false
            #don't set the flag, so that we can exit
        else
            #something unforseen
            echo "$SHARD: $SHARD_STATE"
            echo "SHARD STATE $SHARD_STATE wasn't expected."
            FINAL_RETURN=3
            WAIT_FLAG=false
            #don't set the flag, so that we can exit
        fi
    done


    if $WAIT_FLAG; then
        sleep $WAIT_INTERVAL
    fi
done

if [ $FINAL_RETURN -eq 0 ]; then
    echo "Done waiting successfully"
else
    echo "Failed while waiting for stack, events follow"
    aws cloudformation describe-stack-events --region="$EC2_REGION" --stack-name "$SHARD"
fi

exit $FINAL_RETURN
