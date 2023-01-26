#!/bin/bash
set -x #echo on

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#cloud all
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

#pull in region-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#default region from basic defaults
[ -z $EC2_REGION ] && EC2_REGION=$DEFAULT_REGION

$($LOCAL_PATH/cloud.py --region $EC2_REGION --name $CLOUD_NAME --action export)

#some regions have their own lettering scheme
[ -z $JVB_AZ_LETTER1 ] && JVB_AZ_LETTER1="a"
[ -z $JVB_AZ_LETTER2 ] && JVB_AZ_LETTER2="b"

#VPC to put the stack in
[ -z $VPC_ID ] && VPC_ID="$EC2_VPC_ID"


[ -z "$SSH_AZ" ] && SSH_AZ="${EC2_REGION}${JVB_AZ_LETTER1}"

[ -z "$JVB_SUBNET_AWS_PUBLIC_IPS" ] && JVB_SUBNET_AWS_PUBLIC_IPS="true"

[ -z "$PUBLIC_SUBNET_AWS_PUBLIC_IPS" ] && PUBLIC_SUBNET_AWS_PUBLIC_IPS="true"

SSH_AZ_LETTER="${SSH_AZ: -1}"



eval DEFAULT_PUBLIC_SUBNET_ID=\$DEFAULT_PUBLIC_SUBNET_ID_${SSH_AZ_LETTER}
eval DEFAULT_DC_SUBNET_IDS=\$DEFAULT_DC_SUBNET_IDS_${SSH_AZ_LETTER}

#subnet for public IPs from amazon
[ -z "$PUBLIC_SUBNET_ID" ] && PUBLIC_SUBNET_ID=$DEFAULT_PUBLIC_SUBNET_ID

if [ -z "$PUBLIC_SUBNET_ID" ]; then
    echo "No PUBLIC_SUBNET_ID provided or found.  Exiting without creating stack."
    exit 208
fi

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION

[ -z $CLOUD_PREFIX ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX

[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"

[ -z "$STACK_NAME_PREFIX" ] && STACK_NAME_PREFIX="$CLOUD_PREFIX"

#stack name ends up like: vaas-us-east-1-network
[ -z $STACK_NAME ] && STACK_NAME="${ENVIRONMENT}-${REGION_ALIAS}-${STACK_NAME_PREFIX}-ssh"

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="jitsi-ssh-jumpbox"
 
 #default ssh key for initial EC2 login
[ -z $EC2_KEY_NAME ] && EC2_KEY_NAME="video"

[ -z $DNS_ZONE_ID ] && DNS_ZONE_ID="ZP3DAJR109E5U"
[ -z $DNS_ZONE_DOMAIN_NAME ] && DNS_ZONE_DOMAIN_NAME="infra.jitsi.net"

[ -z "$EC2_IMAGE_ID" ] && EC2_IMAGE_ID=$($LOCAL_PATH/ami.py --batch --type=FocalBase --version=latest --region="$EC2_REGION")
[ -z "$EC2_IMAGE_ID" ] && EC2_IMAGE_ID=$DEFAULT_EC2_IMAGE_ID

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

#Use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="$LOCAL_PATH/../templates/vaas-ssh-jumpbox.template.json"

# ParameterKey=SubnetIds,ParameterValue="$SUBNET_IDS" \

aws cloudformation $CF_OPERATION --region $EC2_REGION --stack-name $STACK_NAME \
--template-body file://$CF_TEMPLATE_JSON \
--parameters ParameterKey=KeyName,ParameterValue=$EC2_KEY_NAME \
ParameterKey=StackNamePrefix,ParameterValue=$STACK_NAME_PREFIX \
ParameterKey=RegionAlias,ParameterValue=$REGION_ALIAS \
ParameterKey=PublicSubnetId,ParameterValue="$PUBLIC_SUBNET_ID" \
ParameterKey=PublicNetworkSecurityGroup,ParameterValue="$SSH_SECURITY_GROUP" \
ParameterKey=DomainName,ParameterValue=$DNS_ZONE_DOMAIN_NAME \
ParameterKey=PublicDNSHostedZoneId,ParameterValue=$DNS_ZONE_ID \
ParameterKey=Ec2ImageId,ParameterValue=$EC2_IMAGE_ID \
ParameterKey=EnvironmentVPCId,ParameterValue=$VPC_ID \
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
"Key=stack-role,Value=ssh" \
--capabilities CAPABILITY_IAM
