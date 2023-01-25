#!/bin/bash
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ACCELERATOR_ARN" ]; then
    echo "No ACCELERATOR_ARN set, exiting"
    exit 2
fi

if [ -z "$CLOUD_NAME" ]; then
    echo "No CLOUD_NAME set, exiting"
    exit 2
fi

. "$LOCAL_PATH/../clouds/$CLOUD_NAME.sh"

set -x

[ -z "$ACCELERATOR_ACTION" ] && ACCELERATOR_ACTION=$1

if [ -z "$ACCELERATOR_ACTION" ]; then
    echo "No ACCELERATOR_ACTION set or passed as first parameter"
    exit 2
fi

case "$ACCELERATOR_ACTION" in

  "drain")
    NEW_PERCENTAGE=0
    ;;

  "ready")
    NEW_PERCENTAGE=100
    ;;

  "set")
    [ -z "$ACCELERATOR_PERCENTAGE" ] && ACCELERATOR_PERCENTAGE=$2
    if [ -z "$ACCELERATOR_PERCENTAGE" ]; then
        echo "Action 'set' requires ACCELERATOR_PERCENTAGE to be set or passed as second parameter"
        exit 3
    fi
    NEW_PERCENTAGE=$ACCELERATOR_PERCENTAGE
    ;;

  *)
    echo "Action not supported: $ACCELERATOR_ACTION"
    exit 3
    ;;
esac

export AWS_DEFAULT_REGION="us-west-2"

LISTENER_ARN=$(aws globalaccelerator list-listeners --accelerator-arn $ACCELERATOR_ARN | jq -r '.Listeners|map(select(.PortRanges[0].FromPort==443))[0].ListenerArn')

if [ $? -eq 0 ]; then
    if [ -z "$LISTENER_ARN" ]; then
        echo "No LISTENER_ARN found, exiting"
        exit 4
    fi
    echo "Accelerator found in environment $ENVIRONMENT: $ACCELERATOR_ARN"
    echo "Listener found on port 443: $LISTENER_ARN"

    ENDPOINT_GROUP=$(aws globalaccelerator list-endpoint-groups --listener-arn $LISTENER_ARN | jq ".EndpointGroups|map(select(.EndpointGroupRegion==\"$EC2_REGION\"))[0]")
    if [ $? -eq 0 ]; then
        if [ -z "$ENDPOINT_GROUP" ]; then
            echo "No ENDPOINT_GROUP found, exiting"
            exit 5
        fi

        ENDPOINT_ARN=$(echo "$ENDPOINT_GROUP" | jq -r '.EndpointGroupArn')
        ENDPOINT_PERCENTAGE=$(echo "$ENDPOINT_GROUP" | jq -r '.TrafficDialPercentage')

        echo "ENDPOINT $ENDPOINT_ARN found in region $EC2_REGION set to traffic $ENDPOINT_PERCENTAGE%"

        if [[ "$NEW_PERCENTAGE" -eq "$ENDPOINT_PERCENTAGE" ]]; then
            echo "ENDPOINT $ENDPOINT_ARN already set to traffic $ENDPOINT_PERCENTAGE%, doing nothing"
        else
            echo "UPDATING ENDPOINT $ENDPOINT_ARN to traffic $NEW_PERCENTAGE%"
            aws globalaccelerator update-endpoint-group --endpoint-group-arn $ENDPOINT_ARN --traffic-dial-percentage $NEW_PERCENTAGE
            FINAL_RET=$?
            if [ $FINAL_RET -eq 0 ]; then
                echo "Success updating endpoint group traffic dial"
            else
                echo "Failure updating endpoint group"
                exit $FINAL_RET
            fi
        fi
    else
        echo "Error listing endpoint groups for acc $ACCELERATOR_ARN listener $LISTENER_ARN"
    fi
else
    echo "Error finding listener for arn $ACCELERATOR_ARN"
    exit 3
fi