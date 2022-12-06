#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

#load cloud defaults
[ -e ../all/clouds/all.sh ] && . ../all/clouds/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/clouds/${CLOUD_NAME}.sh" ] && . ../all/clouds/${CLOUD_NAME}.sh

[ -z "$EC2_AWS_ASN" ] && EC2_AWS_ASN="64512"

[ -z $AZ_REGION ] && AZ_REGION=$EC2_REGION

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$AZ_REGION

$($LOCAL_PATH/bin/cloud.py --action export --name $CLOUD_NAME --region $AZ_REGION --region_alias $REGION_ALIAS)

[ -z "$SERVICE" ] && SERVICE="jitsi-transit-gateway"

[ -z "$STACK_NAME" ] && STACK_NAME="$CLOUD_NAME-transit-gateway-mesh"

CF_TEMPLATE_PATH="$LOCAL_PATH/templates/transit-gateway.template"

describe_stack=$(aws cloudformation describe-stacks --region "$AZ_REGION" --stack-name "$STACK_NAME")
if [ $? -eq 0 ]; then
    stack_status=$(echo $describe_stack|jq -r .Stacks[0].StackStatus)
    if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]; then
        CF_OPERATION='update-stack'
    fi
fi
[ -z "$CF_OPERATION" ] && CF_OPERATION='create-stack'

STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
--template-body file://$CF_TEMPLATE_PATH \
--parameters \
ParameterKey=CloudName,ParameterValue="$CLOUD_NAME" \
ParameterKey=VpcId,ParameterValue="$EC2_VPC_ID" \
ParameterKey=Subnets,ParameterValue="\"$NAT_SUBNET_IDS\"" \
ParameterKey=ASN,ParameterValue=$EC2_AWS_ASN \
--tags "Key=Name,Value=$STACK_NAME" \
"Key=Environment,Value=$ENVIRONMENT_TYPE" \
"Key=Product,Value=$PRODUCT" \
"Key=Team,Value=$TEAM" \
"Key=Service,Value=$SERVICE" \
"Key=Owner,Value=$OWNER" \
"Key=stack-role,Value=transit-gateway")

if [ $? == 0 ]; then
    # Once the stack is built, wait for it to be completed
    STACK_IDS=$(echo $STACK_OUTPUT | jq -r ".StackId")
    export STACK_IDS
    export EC2_REGION
    $LOCAL_PATH/bin/wait-new-stack.sh
    if [ $? == 0 ]; then
        echo "New stack created successfully"
    else
        echo "New stack failed to create correctly"
        exit 213
    fi
else
    echo "Failed when attempting to initiate stack creation"
    echo $STACK_OUTPUT
    exit $?
fi