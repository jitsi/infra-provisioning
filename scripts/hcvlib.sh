#!/usr/bin/env bash

function check_cloudformation_stack_status(){

    region=$1
    stack_name=$2

    describe_stack=$(aws cloudformation describe-stacks --region "$region" --stack-name "$stack_name")
    if [ $? -eq 0 ]; then
        echo "Stack exists. Updating stack."
        CF_OPERATION='update-stack'
    else
        CF_OPERATION='create-stack'
    fi

}

function check_lambda_function_status(){
    region=$1
    lambda_function_name=$2

    aws lambda list-functions --region "$region" | jq -r .Functions[].FunctionArn | grep -q $lambda_function_name
    if [ $? -eq 0 ]; then
        echo "Function exists. Continue creation CF stack."
        return 0
    else
        echo "Function not found. Deploy function $lambda_function_name into region before CF stack creation."
        exit 212
    fi

}


function get_tg_id () {
    STACK_DETAILS="$1"
    TG_ID=$(echo $STACK_DETAILS |jq -r '.Stacks[0].Outputs|map(select(.OutputKey=="TransitGatewayId"))[0].OutputValue')
}

function tg_id_from_cloud () {
    C="$1"
    R="$2"

    # look up current cloud details
    TG_STACK="$C-transit-gateway-mesh"
    stack_details=$(aws cloudformation describe-stacks --region "$R" --stack-name "$TG_STACK")
    if [ $? -eq 0 ]; then
        TG_ID=
        get_tg_id "$stack_details"
        return 0
    else
        echo "Cloudformation stack not found for $TG_STACK"
        return 5
    fi
}

lookup_aws_account_id () {
    AWS_DETAILS=$(aws sts get-caller-identity)
    if [ $? -eq 0 ]; then
        export AWS_ACCOUNT_ID=$(echo $AWS_DETAILS | jq -r '.Account')
        return 0
    else
        return $?
    fi
}