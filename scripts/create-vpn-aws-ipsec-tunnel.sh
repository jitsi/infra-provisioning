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

#TODO ensure secrets are not logged
# Generate a 32 length random key made only out of numbers and characters, as requires by Oracle IPSecTunnel
# Generate first a 40 random bytes, remove invalid characters, then extract up to 32 characters out of it
PSK_VPN1_TUNNEL1=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-32)
PSK_VPN1_TUNNEL2=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-32)

if [ -z $PSK_VPN1_TUNNEL1 ] || [ ${#PSK_VPN1_TUNNEL1} -lt 32 ]; then
  echo "Invalid or empty PSK_VPN1_TUNNEL1, of value $PSK_VPN1_TUNNEL1. Please run the script again to generate a new value."
  exit 210
fi

if [ -z $PSK_VPN1_TUNNEL2 ] || [ ${#PSK_VPN1_TUNNEL2} -lt 32 ]; then
  echo "Invalid or empty PSK_VPN1_TUNNEL2, of value $PSK_VPN1_TUNNEL2. Please run the script again to generate a new value."
  exit 211
fi

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  PSK_VPN2_TUNNEL1=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-32)
  PSK_VPN2_TUNNEL2=$(openssl rand -base64 40 | tr -d "=+/" | cut -c1-32)

  if [ -z $PSK_VPN2_TUNNEL1 ] || [ ${#PSK_VPN2_TUNNEL1} -lt 32 ]; then
    echo "Invalid or empty PSK_VPN2_TUNNEL1, of value $PSK_VPN2_TUNNEL1. Please run the script again to generate a new value."
    exit 212
  fi

  if [ -z $PSK_VPN2_TUNNEL2 ] || [ ${#PSK_VPN2_TUNNEL2} -lt 32 ]; then
    echo "Invalid or empty PSK_VPN2_TUNNEL2, of value $PSK_VPN2_TUNNEL2. Please run the script again to generate a new value."
    exit 213
  fi
fi

# if the transit gateway is specified, update the parameters
TRANSIT_GATEWAY_PARAM=""
if [ ! -z "$TRANSIT_GATEWAY_ID" ]; then
  TRANSIT_GATEWAY_PARAM="--transit_gateway_id $TRANSIT_GATEWAY_ID"
fi

[ -z "$STACK_NAME" ] && STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-ipsec"
#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="jitsi-vpn-aws-oci"

[ -z "$PULL_NETWORK_STACK" ]  &&  PULL_NETWORK_STACK="true"

#use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="/tmp/vaas-ipsec-$REGION_ALIAS.template.json"

check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}

if [ "$CF_OPERATION" == "update-stack" ]; then
  echo "Stack is already created and update operation is not allowed, as it will result in the VPN connections being replaced with new PSK."
  # if we want to allow update, we need to at least use the current PSKs from the VPN connections
  exit 0
fi

[ -z "$CUSTOMER_GATEWAY_STACK_SUFFX" ] && CUSTOMER_GATEWAY_STACK_SUFFX="dummy"
[ -z $CUSTOMER_GATEWAY_STACK_NAME ] && CUSTOMER_GATEWAY_STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-oci-gw-${CUSTOMER_GATEWAY_STACK_SUFFX}"

describe_customer_gw_stack=$(aws cloudformation describe-stacks --region "$AZ_REGION" --stack-name "$CUSTOMER_GATEWAY_STACK_NAME")
if [ $? -eq 0 ]; then
    OCI_GATEWAY_1=$(echo $describe_customer_gw_stack | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"OciGateway1\")) | .[].OutputValue")
    OCI_GATEWAY_2=$(echo $describe_customer_gw_stack | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"OciGateway2\")) | .[].OutputValue")
else
    echo "Failure while getting the details of the stack $CUSTOMER_GATEWAY_STACK_NAME. Exiting..."
    exit 215
fi

#clean current template
cat /dev/null >$CF_TEMPLATE_JSON

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  #generate new template for 2 VPN connections
  $LOCAL_PATH/../templates/create_vpn_aws_ipsec_tunnel.py --region $AZ_REGION --regionalias "$REGION_ALIAS" --stackprefix $STACK_NAME_PREFIX --filepath $CF_TEMPLATE_JSON \
  --pull_network_stack "$PULL_NETWORK_STACK" $TRANSIT_GATEWAY_PARAM

  STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE_JSON \
    --parameters ParameterKey=OciGateway1,ParameterValue="$OCI_GATEWAY_1" \
    ParameterKey=OciGateway2,ParameterValue="$OCI_GATEWAY_2" \
    ParameterKey=PSKVpn1Tunnel1,ParameterValue="$PSK_VPN1_TUNNEL1" \
    ParameterKey=PSKVpn1Tunnel2,ParameterValue="$PSK_VPN1_TUNNEL2" \
    ParameterKey=PSKVpn2Tunnel1,ParameterValue="$PSK_VPN2_TUNNEL1" \
    ParameterKey=PSKVpn2Tunnel2,ParameterValue="$PSK_VPN2_TUNNEL2" \
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
  #generate new template for 1 VPN connection
  $LOCAL_PATH/../templates/create_vpn_aws_ipsec_tunnel.py --region $AZ_REGION --regionalias "$REGION_ALIAS" --stackprefix $STACK_NAME_PREFIX --filepath $CF_TEMPLATE_JSON \
  --pull_network_stack "$PULL_NETWORK_STACK" --single_connection $TRANSIT_GATEWAY_PARAM

  STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
    --template-body file://$CF_TEMPLATE_JSON \
    --parameters ParameterKey=OciGateway1,ParameterValue="$OCI_GATEWAY_1" \
    ParameterKey=PSKVpn1Tunnel1,ParameterValue="$PSK_VPN1_TUNNEL1" \
    ParameterKey=PSKVpn1Tunnel2,ParameterValue="$PSK_VPN1_TUNNEL2" \
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
  ../all/bin/wait-new-stack.sh
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