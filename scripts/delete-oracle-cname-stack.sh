#!/bin/bash

[ -z "$UNIQUE_ID" ] && UNIQUE_ID="$TEST_ID"

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

if [ -z "$UNIQUE_ID" ]; then
  echo "No UNIQUE_ID found. Exiting..."
  exit 201
fi

AZ_REGION="us-east-1"
STACK_NAME="${ENVIRONMENT}-${UNIQUE_ID}-cname"
aws cloudformation delete-stack --region=$AZ_REGION --stack-name $STACK_NAME
if [[ $? -eq 0 ]]; then
    echo "Deleted CNAME cloudformation stack successfully"
else
    echo "Failed to delete CNAME cloudformation stack, please delete by hand"
    exit 3
fi
