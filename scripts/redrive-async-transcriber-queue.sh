#!/bin/bash

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION specified, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$JMR_QUEUE_ID" ]; then
    JMR_QUEUE="$(oci queue queue-admin queue list --all --compartment-id $COMPARTMENT_OCID --region $ORACLE_REGION --output json | jq -r '.data.items[]|select(."display-name"=="multitrack-recorder-'$ENVIRONMENT'")')"
    JMR_QUEUE_ID="$(echo "$JMR_QUEUE" | jq -r '.id')"
    [[ "$JMR_QUEUE_ID" == "null" ]] && JMR_QUEUE_ID=""
    JMR_QUEUE_ENDPOINT="$(echo "$JMR_QUEUE" | jq -r '."messages-endpoint"')"
    [[ "$JMR_QUEUE_ENDPOINT" == "null" ]] && JMR_QUEUE_ENDPOINT=""
fi
if [ -z "$JMR_QUEUE_ID" ]; then
    echo "No JMR_QUEUE_ID set or found in region $ORACLE_REGION compartment $COMPARTMENT_OCID, exiting"
    exit 0
fi
if [ -z "$JMR_QUEUE_ENDPOINT" ]; then
    echo "No JMR_QUEUE_ENDPOINT set or found in region $ORACLE_REGION compartment $COMPARTMENT_OCID, exiting"
    exit 0
fi

$LOCAL_PATH/redrive-queue.sh $JMR_QUEUE_ID $JMR_QUEUE_ENDPOINT
