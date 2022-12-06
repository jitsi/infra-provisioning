#!/bin/bash
set -x #echo on

#load cloud defaults
[ -e ../all/clouds/all.sh ] && . ../all/clouds/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "../all/clouds/${CLOUD_NAME}.sh" ] && . ../all/clouds/${CLOUD_NAME}.sh


#make sure we have a cloud prefix
[ -z $CLOUD_PREFIX ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX

[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"

[ -z "$NAT_SUBNET_A_CIDR" ] && NAT_SUBNET_A_CIDR=$DEFAULT_NAT_SUBNET_A_CIDR
[ -z "$NAT_SUBNET_B_CIDR" ] && NAT_SUBNET_B_CIDR=$DEFAULT_NAT_SUBNET_B_CIDR

[ -z "$NAT_SUBNET_A_CIDRS_IPV6" ] && NAT_SUBNET_A_CIDRS_IPV6=$DEFAULT_NAT_SUBNET_A_CIDRS_IPV6
[ -z "$NAT_SUBNET_B_CIDRS_IPV6" ] && NAT_SUBNET_B_CIDRS_IPV6=$DEFAULT_NAT_SUBNET_B_CIDRS_IPV6

[ -z "$NAT_SUBNET_A_CIDRS_IPV6" ] && NAT_SUBNET_A_CIDRS_IPV6="03::/64"
[ -z "$NAT_SUBNET_B_CIDRS_IPV6" ] && NAT_SUBNET_B_CIDRS_IPV6="04::/64"

#some regions have their own lettering scheme
[ -z $JVB_AZ_LETTER1 ] && JVB_AZ_LETTER1="a"
[ -z $JVB_AZ_LETTER2 ] && JVB_AZ_LETTER2="b"

[ -z "$STACK_NAME_PREFIX" ] && STACK_NAME_PREFIX="$CLOUD_PREFIX"

#region defaults
[ -z "$EC2_REGION" ] && EC2_REGION=$DEFAULT_EC2_REGION

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION

#stack name ends up like: us-east-1-vaas-network
[ -z $STACK_NAME ] && STACK_NAME="${REGION_ALIAS}-${STACK_NAME_PREFIX}-NAT-network"

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="jitsi-nat-network"

#ensure that we use a correct region name
check_current_region_name $EC2_REGION

#use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="/tmp/vaas-nat-network-tmp.template.json"

[ -z "$PULL_NETWORK_STACK" ]  &&  PULL_NETWORK_STACK="true"

describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_NAME")
if [ $? -eq 0 ]; then
    stack_status=$(echo $describe_stack|jq -r .Stacks[0].StackStatus)
    if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]; then
        CF_OPERATION='update-stack'
    else
        echo "Error. Stack status is: $stack_status"
        exit 212
    fi
else
    CF_OPERATION='create-stack'
fi

#clean current template
echo > $CF_TEMPLATE_JSON

#generate new template
../all/templates/create_nat_network_template.py --region "$EC2_REGION" --regionalias "$REGION_ALIAS" --stackprefix "$CLOUD_PREFIX" --filepath $CF_TEMPLATE_JSON \
--pull_network_stack "$PULL_NETWORK_STACK"
# ParameterKey=SubnetIds,ParameterValue="$SUBNET_IDS" \

aws cloudformation "$CF_OPERATION" --region "$EC2_REGION" --stack-name "$STACK_NAME" \
--template-body "file://$CF_TEMPLATE_JSON" \
--parameters ParameterKey=StackNamePrefix,ParameterValue="$STACK_NAME_PREFIX" \
ParameterKey=RegionAlias,ParameterValue="$REGION_ALIAS" \
ParameterKey=AZ1Letter,ParameterValue="$JVB_AZ_LETTER1" \
ParameterKey=AZ2Letter,ParameterValue="$JVB_AZ_LETTER2" \
ParameterKey=NATSubnetACidr,ParameterValue="\"$NAT_SUBNET_A_CIDR\"" \
ParameterKey=NATSubnetBCidr,ParameterValue="\"$NAT_SUBNET_B_CIDR\"" \
ParameterKey=NATSubnetACidrIPv6,ParameterValue="$NAT_SUBNET_A_CIDRS_IPV6" \
ParameterKey=NATSubnetBCidrIPv6,ParameterValue="$NAT_SUBNET_B_CIDRS_IPV6" \
ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
ParameterKey=TagTeam,ParameterValue="$TEAM" \
ParameterKey=TagOwner,ParameterValue="$OWNER" \
ParameterKey=TagService,ParameterValue="$SERVICE" \
--tags "Key=Name,Value=$STACK_NAME" \
"Key=Environment,Value=$ENVIRONMENT_TYPE" \
"Key=Product,Value=$PRODUCT" \
"Key=Team,Value=$TEAM" \
"Key=Service,Value=$SERVICE" \
"Key=Owner,Value=$OWNER" \
"Key=stack-role,Value=NAT-network" \
--capabilities CAPABILITY_IAM
