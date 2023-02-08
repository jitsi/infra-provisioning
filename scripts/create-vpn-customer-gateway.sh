#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh
[ -e $LOCAL_PATH/hcvlib.sh ] && . $LOCAL_PATH/hcvlib.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#make sure we have a cloud prefix
[ -z $CLOUD_PREFIX ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX
[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"
[ -z "$AZ_REGION" ] && AZ_REGION=$EC2_REGION
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT
[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$AZ_REGION
[ -z "$STACK_NAME_PREFIX" ] && STACK_NAME_PREFIX="$CLOUD_PREFIX"

# We need an envirnment "all"
if [ -z $ENVIRONMENT ]; then
  echo "No Environment provided or found.  Exiting without creating stack."
  exit 202
fi

[ -z "$CUSTOMER_GATEWAY_IP1" ] && CUSTOMER_GATEWAY_IP1="1.1.1.1"
[ -z "$CUSTOMER_GATEWAY_IP2" ] && CUSTOMER_GATEWAY_IP2="1.1.1.2"
[ -z "$CUSTOMER_GATEWAY_STACK_SUFFX" ] && CUSTOMER_GATEWAY_STACK_SUFFX="dummy"

[ -z "$STACK_NAME" ] && STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-oci-gw-${CUSTOMER_GATEWAY_STACK_SUFFX}"
#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="jitsi-vpn-aws-oci"

#use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="/tmp/vaas-oci-customer-gw-$REGION_ALIAS.template.json"

check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}

if [ "$CF_OPERATION" == "update-stack" ]; then
  echo "Stack is already created and update operation is not allowed, as it will result most likely in the gateway replacement."
  #ensure the user knows what is doing
  check_current_region_name $STACK_NAME
fi

#clean current template
cat /dev/null >$CF_TEMPLATE_JSON

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  #generate new template with 2 connections
  $LOCAL_PATH/../templates/create_vpn_customer_gateway.py --stackprefix $STACK_NAME_PREFIX --filepath $CF_TEMPLATE_JSON

  STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE_JSON \
    --parameters ParameterKey=OciGatewayIP1,ParameterValue="$CUSTOMER_GATEWAY_IP1" \
    ParameterKey=OciGatewayIP2,ParameterValue="$CUSTOMER_GATEWAY_IP2" \
    ParameterKey=RegionAlias,ParameterValue="$REGION_ALIAS" \
    ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
    ParameterKey=TagEnvironment,ParameterValue=$ENVIRONMENT \
    ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
    ParameterKey=TagTeam,ParameterValue="$TEAM" \
    ParameterKey=TagOwner,ParameterValue="$OWNER" \
    ParameterKey=TagService,ParameterValue="$SERVICE" \
    ParameterKey=TagRole,ParameterValue="vpn-aws-oci" \
    --tags "Key=Name,Value=$STACK_NAME" \
    "Key=Environment,Value=$ENVIRONMENT_TYPE" \
    "Key=environment,Value=$ENVIRONMENT" \
    "Key=Product,Value=$PRODUCT" \
    "Key=Team,Value=$TEAM" \
    "Key=Owner,Value=$OWNER" \
    "Key=Service,Value=$SERVICE" \
    "Key=stack-role,Value=vpn-aws-oci")
else
  #generate new template with 1 connection
  $LOCAL_PATH/../templates/create_vpn_customer_gateway.py --stackprefix $STACK_NAME_PREFIX --filepath $CF_TEMPLATE_JSON --single_connection

  STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE_JSON \
    --parameters ParameterKey=OciGatewayIP1,ParameterValue="$CUSTOMER_GATEWAY_IP1" \
    ParameterKey=RegionAlias,ParameterValue="$REGION_ALIAS" \
    ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
    ParameterKey=TagEnvironment,ParameterValue=$ENVIRONMENT \
    ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
    ParameterKey=TagTeam,ParameterValue="$TEAM" \
    ParameterKey=TagOwner,ParameterValue="$OWNER" \
    ParameterKey=TagService,ParameterValue="$SERVICE" \
    ParameterKey=TagRole,ParameterValue="vpn-aws-oci" \
    --tags "Key=Name,Value=$STACK_NAME" \
    "Key=Environment,Value=$ENVIRONMENT_TYPE" \
    "Key=environment,Value=$ENVIRONMENT" \
    "Key=Product,Value=$PRODUCT" \
    "Key=Team,Value=$TEAM" \
    "Key=Owner,Value=$OWNER" \
    "Key=Service,Value=$SERVICE" \
    "Key=stack-role,Value=vpn-aws-oci")

fi

if [ $? == 0 ]; then
  # Once the stack is built, wait for it to be completed
  STACK_IDS=$(echo $STACK_OUTPUT | jq -r ".StackId")
  export STACK_IDS
  export EC2_REGION
  $LOCAL_PATH/wait-new-stack.sh
  if [ $? == 0 ]; then
    echo "New stack created successfully"
    exit 0
  else
    echo "New stack failed to create correctly"
    exit 213
  fi
else
  RESULT=$?
  echo "Failed when attempting to initiate stack creation"
  echo $STACK_OUTPUT
  exit $RESULT
fi


