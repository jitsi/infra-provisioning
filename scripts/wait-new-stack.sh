#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "../all/clouds/${CLOUD_NAME}.sh" ] && . ../all/clouds/${CLOUD_NAME}.sh

export AWS_DEFAULT_REGION="$EC2_REGION"

if [ -z "$STACK_IDS" ]; then

    [ -z $STACK_DATA_PATH ] && STACK_DATA_PATH=$1

    if [ -z $STACK_DATA_PATH ]; then
        echo "No stack cloudformation templates specified either in command line or in STACK_DATA_PATH variable"
        exit 10
    fi
fi

if [ -z "$STACK_IDS" ]; then
    STACK_IDS=$(cat $STACK_DATA_PATH | jq -r ".StackId")

    if [[ $? != 0 ]] || [ -z "$STACK_IDS" ]; then
        echo "No stack ids found in cat $STACK_DATA_PATH | jq -r \".StackId\""
        exit 11
    fi
fi
#optimistic
FINAL_RETURN=0

#wait a bit
WAIT_INTERVAL=60

WAIT_FLAG=true
while $WAIT_FLAG; do
    WAIT_FLAG=false
    for STACK in $STACK_IDS; do
        STACK_STATE=$(aws cloudformation describe-stacks --region="$EC2_REGION" --stack "$STACK" | jq -r ".Stacks[0].StackStatus")
        if [ "x$STACK_STATE" == "xCREATE_COMPLETE" ]; then
            #success
            #don't set the flag, so that we can exit
            #now check the next one
            echo "$STACK: $STACK_STATE"
        elif [ "x$STACK_STATE" == "xUPDATE_COMPLETE" ]; then
            #success
            #don't set the flag, so that we can exit
            #now check the next one
            echo "$STACK: $STACK_STATE"
        elif [ "x$STACK_STATE" == "xCREATE_IN_PROGRESS" ]; then
            #keep waiting
            echo "$STACK: $STACK_STATE"
            WAIT_FLAG=true
            WAIT_TYPE="stack-create-complete"
        elif [ "x$STACK_STATE" == "xUPDATE_IN_PROGRESS" ]; then
            #keep waiting
            echo "$STACK: $STACK_STATE"
            WAIT_FLAG=true
            WAIT_TYPE="stack-update-complete"
        elif [ "x$STACK_STATE" == "xUPDATE_COMPLETE_CLEANUP_IN_PROGRESS" ]; then
            #keep waiting
            echo "$STACK: $STACK_STATE"
            WAIT_FLAG=true
            WAIT_TYPE="stack-update-complete"
        elif [ "x$STACK_STATE" == "xROLLBACK_IN_PROGRESS" ]; then
            #failure of a sort
            echo "$STACK: $STACK_STATE"
            FINAL_RETURN=1
            WAIT_FLAG=false
            #don't set the flag, so that we can exit

        elif [ "x$STACK_STATE" == "xROLLBACK_COMPLETE" ]; then
            #failure of a sort
            echo "$STACK: $STACK_STATE"
            FINAL_RETURN=2
            WAIT_FLAG=false
            #don't set the flag, so that we can exit
        else
            #something unforseen
            echo "$STACK: $STACK_STATE"
            echo "STACK STATE $STACK_STATE wasn't expected."
            FINAL_RETURN=3
            WAIT_FLAG=false
            #don't set the flag, so that we can exit
        fi
    done

    if $WAIT_FLAG; then
        aws cloudformation wait $WAIT_TYPE --region="$EC2_REGION" --stack "$STACK"
    fi
done

if [ $FINAL_RETURN -eq 0 ]; then
    echo "Done waiting successfully"
else
    echo "Failed while waiting for stack, events follow"
    aws cloudformation describe-stack-events --region="$EC2_REGION" --stack-name "$STACK"
fi
exit $FINAL_RETURN
