#!/bin/bash
set -x #echo on
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh


#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh
[ -e $LOCAL_PATH/hcvlib.sh ] && . $LOCAL_PATH/hcvlib.sh
#default cloud if not set
[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#make sure we have a cloud prefix
[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX
[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"
[ -z "$AZ_REGION" ] && AZ_REGION=$EC2_REGION
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT
[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$AZ_REGION
[ -z "$STACK_NAME_PREFIX" ] && STACK_NAME_PREFIX="$CLOUD_PREFIX"

#SINGLE_CONNECTION_FLAG indicates whether to create 1 (true) or 2 (default) connections
if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  echo "Creating VPN with two IPSEC connections"
else
  echo "Creating VPN with single IPSEC connection"
fi

export SINGLE_CONNECTION_FLAG
export CLOUD_NAME
export CLOUD_PREFIX
export AZ_REGION
export REGION_ALIAS
export SHARD_BASE
export STACK_NAME_PREFIX

# This is needed for testing, in regions where the network was created by hand
[ -z $CREATE_AWS_VPN_NETWORK ] && CREATE_AWS_VPN_NETWORK=true

if $CREATE_AWS_VPN_NETWORK; then
  # Create the AWS VPN network stack which applies to all environments in the CLOUD_NAME
  STACK_NAME="${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-aws-oci-network"
  check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}
  if [ "$CF_OPERATION" == "create-stack" ]; then
    echo "[AWS Side] Creating AWS VPN network stack for cloud $CLOUD_NAME"
    $LOCAL_PATH/create-vpn-aws-network.sh
    if [ $? -gt 0 ]; then
      echo "[AWS Side]AWS VPN network stack creation failed. Exiting..."
      exit 4
    fi
  else
    echo "[AWS Side] AWS VPN network stack already exists. Skipping its creation."
  fi
  unset STACK_NAME
else
  echo "[AWS Side] AWS VPN network creation is skipped, as CREATE_AWS_VPN_NETWORK is $CREATE_AWS_VPN_NETWORK"
fi

# We export environment only after the VPN Network creation, as the Network will apply to 'all' environments
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found.  Exiting without creating VPN stacks."
  exit 202
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

export ENVIRONMENT
export ORACLE_REGION
export DEFAULT_VPC_CIDR

echo "Creating VPN for environment $ENVIRONMENT and cloud $CLOUD_NAME"
sleep 10

#########################################################
# VPN Connections on AWS side using Dummy Customer Gateway
#########################################################

echo "[AWS Side] Creating dummy OCI customer gateways"
export CUSTOMER_GATEWAY_IP1="1.$((1 + RANDOM % 20)).1.$((1 + RANDOM % 20))"
[ -z "$SINGLE_CONNECTION_FLAG" ] && export CUSTOMER_GATEWAY_IP2="1.$((20 + RANDOM % 10)).1.$((20 + RANDOM % 10))"
export CUSTOMER_GATEWAY_STACK_SUFFX="dummy"
export STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-oci-gw-${CUSTOMER_GATEWAY_STACK_SUFFX}"
check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}
if [ "$CF_OPERATION" == "create-stack" ]; then
  echo "[AWS Side] Creating AWS dummy OCI customer gateways stack $STACK_NAME"
  $LOCAL_PATH/create-vpn-customer-gateway.sh
  if [ $? -gt 0 ]; then
    echo "[AWS Side] OCI dummy customer gateways creation failed. Exiting..."
    exit 5
  fi
else
  echo "[AWS Side] Dummy OCI customer gateway stack already exists. Skipping its creation."
fi
unset STACK_NAME

echo "[AWS Side] Creating VPN connections using dummy gateways"
export AWS_VPN_GATEWAY_ID
export STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-ipsec"
check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}
if [ "$CF_OPERATION" == "create-stack" ]; then
  echo "[AWS Side] Creating VPN connection stack $STACK_NAME"
  $LOCAL_PATH/create-vpn-aws-ipsec-tunnel.sh
  if [ $? -gt 0 ]; then
    echo "[AWS Side] VPN connections creation failed. Exiting..."
    exit 6
  fi
else
  echo "[AWS Side] VPN connections stack already exists. Skipping its creation."
fi

# Extract VPNs cpnfiguration (e.g. tunnel 1 pre-shared key, public ip)
describe_customer_gw_stack=$(aws cloudformation describe-stacks --region "$AZ_REGION" --stack-name "$STACK_NAME")
if [ $? -eq 0 ]; then
  AWS_VPN_CONNECTION_ID_1=$(echo "$describe_customer_gw_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"VpnConnectionId1\")) | .[].OutputValue")
  [ -z "$SINGLE_CONNECTION_FLAG" ] && AWS_VPN_CONNECTION_ID_2=$(echo "$describe_customer_gw_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"VpnConnectionId2\")) | .[].OutputValue")
else
  echo "Failure while getting the details of the stack $STACK_NAME. Exiting..."
  exit 215
fi

VPN_CONFIGURATION_OUTPUT="/tmp/vpn-configuration-output_1.xml"
aws ec2 describe-vpn-connections --region "$AZ_REGION" --filters "Name=vpn-connection-id,Values=$AWS_VPN_CONNECTION_ID_1" | jq -r '.VpnConnections[0].CustomerGatewayConfiguration' >$VPN_CONFIGURATION_OUTPUT
VPN_1_CONFIG_JSON=$($LOCAL_PATH/parse_vpn_configuration.py --filepath $VPN_CONFIGURATION_OUTPUT)

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  VPN_CONFIGURATION_OUTPUT="/tmp/vpn-configuration-output_2.xml"
  aws ec2 describe-vpn-connections --region "$AZ_REGION" --filters "Name=vpn-connection-id,Values=$AWS_VPN_CONNECTION_ID_2" | jq -r '.VpnConnections[0].CustomerGatewayConfiguration' >$VPN_CONFIGURATION_OUTPUT
  VPN_2_CONFIG_JSON=$($LOCAL_PATH/parse_vpn_configuration.py --filepath $VPN_CONFIGURATION_OUTPUT)
fi

unset STACK_NAME

################################################
# VPN Network prerequisites in Oracle
################################################

echo "[Oracle Side] Creating VPN network pre-requisites (DRG, drg-attachment, route table rules, public & private security list rules) for region $ORACLE_REGION"
$LOCAL_PATH/vpn-network-prerequisites-oracle.sh
if [ $? -gt 0 ]; then
  echo "[Oracle Side] Failure while creating the VPN network pre-requisites. Exiting..."
  exit 220
fi

################################################
# VPN Connections on Oracle Side pointing to AWS
################################################

AWS_TUNNEL_1_VPN_INSIDE_IP="$(echo "$VPN_1_CONFIG_JSON" | jq -r '."vpn_inside_ip"')"
AWS_TUNNEL_1_VPN_INSIDE_NETWORK_CIDR="$(echo "$VPN_1_CONFIG_JSON" | jq -r '."vpn_inside_network_cidr"')"
AWS_TUNNEL_1_CST_INSIDE_IP="$(echo "$VPN_1_CONFIG_JSON" | jq -r '."cst_inside_ip"')"
AWS_TUNNEL_1_CST_INSIDE_NETWORK_CIDR="$(echo "$VPN_1_CONFIG_JSON" | jq -r '."cst_inside_network_cidr"')"
export AWS_TUNNEL_1_VIRTUAL_PRIVATE_GATEWAY=$AWS_TUNNEL_1_VPN_INSIDE_IP/$AWS_TUNNEL_1_VPN_INSIDE_NETWORK_CIDR
export AWS_TUNNEL_1_CUSTOMER_GATEWAY=$AWS_TUNNEL_1_CST_INSIDE_IP/$AWS_TUNNEL_1_CST_INSIDE_NETWORK_CIDR
export AWS_TUNNEL_1_PRE_SHARED_KEY="$(echo "$VPN_1_CONFIG_JSON" | jq -r '.psk')"
export AWS_TUNNEL_1_IP_ADDRESS="$(echo "$VPN_1_CONFIG_JSON" | jq -r '."vpn_public_ip"')"

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then

  AWS_TUNNEL_2_VPN_INSIDE_IP="$(echo "$VPN_2_CONFIG_JSON" | jq -r '."vpn_inside_ip"')"
  AWS_TUNNEL_2_VPN_INSIDE_NETWORK_CIDR="$(echo "$VPN_2_CONFIG_JSON" | jq -r '."vpn_inside_network_cidr"')"
  AWS_TUNNEL_2_CST_INSIDE_IP="$(echo "$VPN_2_CONFIG_JSON" | jq -r '."cst_inside_ip"')"
  AWS_TUNNEL_2_CST_INSIDE_NETWORK_CIDR="$(echo "$VPN_2_CONFIG_JSON" | jq -r '."cst_inside_network_cidr"')"
  export AWS_TUNNEL_2_VIRTUAL_PRIVATE_GATEWAY=$AWS_TUNNEL_2_VPN_INSIDE_IP/$AWS_TUNNEL_2_VPN_INSIDE_NETWORK_CIDR
  export AWS_TUNNEL_2_CUSTOMER_GATEWAY=$AWS_TUNNEL_2_CST_INSIDE_IP/$AWS_TUNNEL_2_CST_INSIDE_NETWORK_CIDR
  export AWS_TUNNEL_2_PRE_SHARED_KEY="$(echo "$VPN_2_CONFIG_JSON" | jq -r '.psk')"
  export AWS_TUNNEL_2_IP_ADDRESS="$(echo "$VPN_2_CONFIG_JSON" | jq -r '."vpn_public_ip"')"
fi

echo "[Oracle Side] Creating VPN connections"
$LOCAL_PATH/terraform/create-vpn-oracle-ipsec-tunnel/create-vpn-oracle-ipsec-tunnel.sh
if [ $? -gt 0 ]; then
  echo "[Oracle Side] Failure while creating the VPN connection. Exiting..."
  exit 218
fi

########################################################
# VPN Connections on AWS side using OCI Customer Gateway
########################################################

echo "[AWS Side] Creating final OCI customer gateways"

. $LOCAL_PATH/terraform/vpn-oracle-ipsec-tunnel-state/get-vpn-oracle-ipsec-tunnel-state.sh
if [ $? -gt 0 ]; then
  echo "[Oracle Side] Failure while extracting the Customer Gateway IPs. Exiting..."
  exit 219
fi

export CUSTOMER_GATEWAY_STACK_SUFFX="final"
export STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-oci-gw-${CUSTOMER_GATEWAY_STACK_SUFFX}"
check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}
if [ "$CF_OPERATION" == "create-stack" ]; then
  echo "[AWS Side] Creating AWS final OCI customer gateways stack $STACK_NAME"
  $LOCAL_PATH/create-vpn-customer-gateway.sh
  if [ $? -gt 0 ]; then
    echo "[AWS Side] OCI final customer gateways creation failed. Exiting..."
    exit 6
  fi
else
  echo "[AWS Side] Final OCI customer gateway stack already exists. Skipping its creation."
fi

# Update VPN Connections with the new customer gateways
describe_customer_gw_stack=$(aws cloudformation describe-stacks --region "$AZ_REGION" --stack-name "$STACK_NAME")
if [ $? -eq 0 ]; then
  OCI_GATEWAY_1=$(echo "$describe_customer_gw_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"OciGateway1\")) | .[].OutputValue")
  if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
    OCI_GATEWAY_2=$(echo "$describe_customer_gw_stack" | jq -r ".Stacks[].Outputs | map(select(.OutputKey==\"OciGateway2\")) | .[].OutputValue")
  fi
else
  echo "Failure while getting the details of the stack $STACK_NAME. Exiting..."
  exit 216
fi

unset STACK_NAME

aws ec2 modify-vpn-connection --region "$AZ_REGION" --vpn-connection-id "$AWS_VPN_CONNECTION_ID_1" --customer-gateway-id "$OCI_GATEWAY_1"
if [ $? -gt 0 ]; then
  echo "[AWS Side] Something went wrong while modifying the VPN connection with the new customer gateway. Exiting..."
  exit 6
fi

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then

  aws ec2 modify-vpn-connection --region "$AZ_REGION" --vpn-connection-id "$AWS_VPN_CONNECTION_ID_2" --customer-gateway-id "$OCI_GATEWAY_2"
  if [ $? -gt 0 ]; then
    echo "[AWS Side] Something went wrong while modifying the VPN connection with the new customer gateway. Exiting..."
    exit 7
  fi
fi

# This operation will probably take a while until it is done
VPN_UPDATE_RESULT=0
WAIT_INTERVAL=60
WAIT_FLAG=true
while $WAIT_FLAG; do
  WAIT_FLAG=false

  VPN_CONN_1_STATE=$(aws ec2 describe-vpn-connections --region "$AZ_REGION" --filters "Name=vpn-connection-id,Values=$AWS_VPN_CONNECTION_ID_1" | jq -r '.VpnConnections[0].State')
  echo "VPN_CONN_1_STATUS=$VPN_CONN_1_STATE"
  if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
    VPN_CONN_2_STATE=$(aws ec2 describe-vpn-connections --region "$AZ_REGION" --filters "Name=vpn-connection-id,Values=$AWS_VPN_CONNECTION_ID_2" | jq -r '.VpnConnections[0].State')
    echo "VPN_CONN_2_STATUS=$VPN_CONN_2_STATE"
  fi


  if [ -z "$SINGLE_CONNECTION_FLAG" ]; then

    if [ "$VPN_CONN_1_STATE" == "available" ] && [ "$VPN_CONN_2_STATE" == "available" ]; then
      WAIT_FLAG=false
      VPN_UPDATE_RESULT=0
    elif [ "$VPN_CONN_1_STATE" == "pending" ] || [ "$VPN_CONN_2_STATE" == "pending" ]; then
      WAIT_FLAG=true
    elif [ "$VPN_CONN_1_STATE" == "modifying" ] || [ "$VPN_CONN_2_STATE" == "modifying" ]; then
      WAIT_FLAG=true
    else
      WAIT_FLAG=false
      VPN_UPDATE_RESULT=217
    fi
  else
    if [ "$VPN_CONN_1_STATE" == "available" ]; then
      WAIT_FLAG=false
      VPN_UPDATE_RESULT=0
    elif [ "$VPN_CONN_1_STATE" == "pending" ]; then
      WAIT_FLAG=true
    elif [ "$VPN_CONN_1_STATE" == "modifying" ]; then
      WAIT_FLAG=true
    else
      WAIT_FLAG=false
      VPN_UPDATE_RESULT=217
    fi
  fi
  if $WAIT_FLAG; then
    sleep $WAIT_INTERVAL
  fi
done

if [ $VPN_UPDATE_RESULT -gt 0 ]; then
  echo "Updating the VPN connections with the new customer gateway failed. Exititng..."
  exit $VPN_UPDATE_RESULT
fi

# Now delete the dummy stack
export DUMMY_CUSTOMER_GW_STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-vpn-oci-gw-dummy"
aws cloudformation delete-stack --region "$AZ_REGION" --stack-name "$DUMMY_CUSTOMER_GW_STACK_NAME"
