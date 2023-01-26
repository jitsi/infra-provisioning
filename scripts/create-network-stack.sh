#!/bin/bash
set -x #echo on

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#make sure we have a cloud prefix
[ -z $CLOUD_PREFIX ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX

[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"


[ -z $ENABLE_IPV6 ] && ENABLE_IPV6="true"

#use default VPC_CIDR if one is not provide
[ -z "$VPC_CIDR" ] && VPC_CIDR="$DEFAULT_VPC_CIDR"

[ -z "$JVB_SUBNET_A_CIDRS" ] && JVB_SUBNET_A_CIDRS=$DEFAULT_JVB_SUBNET_A_CIDRS
[ -z "$JVB_SUBNET_B_CIDRS" ] && JVB_SUBNET_B_CIDRS=$DEFAULT_JVB_SUBNET_B_CIDRS

[ -z "$PUBLIC_SUBNET_A_CIDRS" ] && PUBLIC_SUBNET_A_CIDRS=$DEFAULT_PUBLIC_SUBNET_A_CIDRS
[ -z "$PUBLIC_SUBNET_B_CIDRS" ] && PUBLIC_SUBNET_B_CIDRS=$DEFAULT_PUBLIC_SUBNET_B_CIDRS


[ -z "$JVB_SUBNET_A_CIDRS_IPV6" ] && JVB_SUBNET_A_CIDRS_IPV6=$DEFAULT_JVB_SUBNET_A_CIDRS_IPV6
[ -z "$JVB_SUBNET_B_CIDRS_IPV6" ] && JVB_SUBNET_B_CIDRS_IPV6=$DEFAULT_JVB_SUBNET_B_CIDRS_IPV6

[ -z "$PUBLIC_SUBNET_A_CIDRS_IPV6" ] && PUBLIC_SUBNET_A_CIDRS_IPV6=$DEFAULT_PUBLIC_SUBNET_A_CIDRS_IPV6
[ -z "$PUBLIC_SUBNET_B_CIDRS_IPV6" ] && PUBLIC_SUBNET_B_CIDRS_IPV6=$DEFAULT_PUBLIC_SUBNET_B_CIDRS_IPV6

[ -z "$JVB_SUBNET_A_CIDRS_IPV6" ] && JVB_SUBNET_A_CIDRS_IPV6="a1::/64,a2::/64"
[ -z "$JVB_SUBNET_B_CIDRS_IPV6" ] && JVB_SUBNET_B_CIDRS_IPV6="b1::/64,b2::/64"

[ -z "$PUBLIC_SUBNET_A_CIDRS_IPV6" ] && PUBLIC_SUBNET_A_CIDRS_IPV6="01::/64"
[ -z "$PUBLIC_SUBNET_B_CIDRS_IPV6" ] && PUBLIC_SUBNET_B_CIDRS_IPV6="02::/64"

#some regions have their own lettering scheme
[ -z $JVB_AZ_LETTER1 ] && JVB_AZ_LETTER1="a"
[ -z $JVB_AZ_LETTER2 ] && JVB_AZ_LETTER2="b"

[ -z "$PAGERDUTY_SNSTOPICNAME" ] && PAGERDUTY_SNSTOPICNAME="PagerDutyAlarms"

[ -z "$STACK_NAME_PREFIX" ] && STACK_NAME_PREFIX="$CLOUD_PREFIX"

[ -z "$JVB_SUBNET_AWS_PUBLIC_IPS" ] && JVB_SUBNET_AWS_PUBLIC_IPS="true"

[ -z "$PUBLIC_SUBNET_AWS_PUBLIC_IPS" ] && PUBLIC_SUBNET_AWS_PUBLIC_IPS="true"

#region defaults
[ -z "$EC2_REGION" ] && EC2_REGION=$DEFAULT_EC2_REGION

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION

#stack name ends up like: us-east-1-vaas-network
[ -z $STACK_NAME ] && STACK_NAME="${REGION_ALIAS}-${STACK_NAME_PREFIX}-network"


 #default ssh key for initial EC2 login on ssh gateway
[ -z $EC2_KEY_NAME ] && EC2_KEY_NAME="video"

#Look up base image
[ -z "$EC2_IMAGE_ID" ] && EC2_IMAGE_ID=$($LOCAL_PATH/ami.py --batch --type=FocalBase --version=latest --region="$EC2_REGION")

#No image was found, probably not built yet?
if [ -z "$EC2_IMAGE_ID" ]; then
    echo "No FocalBase image provided or found.  Exiting without creating stack."
    exit 210
fi

#[ -z "$EC2_IMAGE_ID" ] && EC2_IMAGE_ID=$DEFAULT_EC2_IMAGE_ID

[ -z "$JUMPBOX_INSTANCE_TYPE" ] && JUMPBOX_INSTANCE_TYPE="t3.large"

[ -z $DNS_ZONE_ID ] && DNS_ZONE_ID="ZP3DAJR109E5U"
[ -z $DNS_ZONE_DOMAIN_NAME ] && DNS_ZONE_DOMAIN_NAME="infra.jitsi.net"

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="jitsi-network"

[ -z $VPC_PEERING_STATUS_TAG ] && VPC_PEERING_STATUS_TAG='false'

[ -z "$AUTOASSIGN_IPV6_LAMBDA_NAME" ] && AUTOASSIGN_IPV6_LAMBDA_NAME='all-cf-manage-autoaassign-ipv6'

describe_lambda_functions=$(aws lambda list-functions --region "$EC2_REGION" | jq -r .Functions[].FunctionArn | grep -q $AUTOASSIGN_IPV6_LAMBDA_NAME)
if [ $? -eq 0 ]; then
    echo "Function exists. Continue creation CF stack."
else
    echo "Function not found. Deploy function $AUTOASSIGN_IPV6_LAMBDA_NAME into region before CF stack creation."
    exit 212
fi

#ensure that we use a correct stack name
check_current_region_name $STACK_NAME

describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_NAME")

if [ $? -eq 0 ]; then
    stack_status=$(echo $describe_stack | jq -r '.Stacks[0].StackStatus' )
    if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_ROLLBACK_COMPLETE" ]; then
        CF_OPERATION='update-stack'
    else
        echo "Error. Stack status is: $stack_status"
        exit 212
    fi
else
    CF_OPERATION='create-stack'
fi


# if [ "$CF_OPERATION" == 'update-stack' ]; then
#     STACK_VPC_ID=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_NAME"|jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="VPC")|.OutputValue')
#     STACK_IPV6_STATUS=$(aws ec2 describe-vpcs --region "$EC2_REGION" --vpc-ids "$STACK_VPC_ID"|jq -r '.Vpcs[].Ipv6CidrBlockAssociationSet[].Ipv6CidrBlockState|select(.State=="associated")|.State')
#     if [ $? -eq 0 ] && [ "$(echo $ENABLE_IPV6|tr '[:upper:]' '[:lower:]')" == 'true' ] && [ "$STACK_IPV6_STATUS" == 'associated' ]; then
#         echo -e 'IPv6 has already been activated in this Stack.\nAWS has a limit for the IPv6 CIDR.\nSkip stack creation'
#         exit 213
#     fi
# fi

#Use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="/tmp/vaas-network-tmp.template.json"


network_template_generator () {
    #clean current template
    cat /dev/null > $CF_TEMPLATE_JSON
    #generate new template
    $LOCAL_PATH/../templates/create_network_template.py --filepath $CF_TEMPLATE_JSON --stackprefix $STACK_NAME_PREFIX $*
    aws s3 cp $CF_TEMPLATE_JSON s3://jitsi-cf-templates/network/$STACK_NAME.json
}

create_aws_network_stack () {
    STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region $EC2_REGION --stack-name $STACK_NAME \
    --template-url https://s3.amazonaws.com/jitsi-cf-templates/network/$STACK_NAME.json \
    --parameters ParameterKey=StackNamePrefix,ParameterValue=$STACK_NAME_PREFIX \
    ParameterKey=RegionAlias,ParameterValue="$REGION_ALIAS" \
    ParameterKey=VPCCidr,ParameterValue="$VPC_CIDR" \
    ParameterKey=AZ1Letter,ParameterValue="$JVB_AZ_LETTER1" \
    ParameterKey=AZ2Letter,ParameterValue="$JVB_AZ_LETTER2" \
    ParameterKey=AppInstanceType,ParameterValue="$JUMPBOX_INSTANCE_TYPE" \
    ParameterKey=JVBSubnetMapPublicIp,ParameterValue="$JVB_SUBNET_AWS_PUBLIC_IPS" \
    ParameterKey=JVBSubnetACidrs,ParameterValue=\"$JVB_SUBNET_A_CIDRS\" \
    ParameterKey=JVBSubnetBCidrs,ParameterValue=\"$JVB_SUBNET_B_CIDRS\" \
    ParameterKey=PublicSubnetACidr,ParameterValue="$PUBLIC_SUBNET_A_CIDRS" \
    ParameterKey=PublicSubnetBCidr,ParameterValue="$PUBLIC_SUBNET_B_CIDRS" \
    ParameterKey=PublicSubnetMapPublicIp,ParameterValue="$PUBLIC_SUBNET_AWS_PUBLIC_IPS" \
    ParameterKey=JVBSubnetACidrsIPv6,ParameterValue=\"$JVB_SUBNET_A_CIDRS_IPV6\" \
    ParameterKey=JVBSubnetBCidrsIPv6,ParameterValue=\"$JVB_SUBNET_B_CIDRS_IPV6\" \
    ParameterKey=PublicSubnetACidrIPv6,ParameterValue="$PUBLIC_SUBNET_A_CIDRS_IPV6" \
    ParameterKey=PublicSubnetBCidrIPv6,ParameterValue="$PUBLIC_SUBNET_B_CIDRS_IPV6" \
    ParameterKey=DomainName,ParameterValue=$DNS_ZONE_DOMAIN_NAME \
    ParameterKey=PublicDNSHostedZoneId,ParameterValue=$DNS_ZONE_ID \
    ParameterKey=KeyName,ParameterValue=$EC2_KEY_NAME \
    ParameterKey=Ec2ImageId,ParameterValue=$EC2_IMAGE_ID \
    ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
    ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
    ParameterKey=TagTeam,ParameterValue="$TEAM" \
    ParameterKey=TagOwner,ParameterValue="$OWNER" \
    ParameterKey=TagService,ParameterValue="$SERVICE" \
    ParameterKey=AutoassignIpv6LambdaFunctionName,ParameterValue=$AUTOASSIGN_IPV6_LAMBDA_NAME \
    ParameterKey=TagVPCpeeringStatus,ParameterValue=$VPC_PEERING_STATUS_TAG \
    --tags "Key=Name,Value=$STACK_NAME" \
    "Key=Environment,Value=$ENVIRONMENT_TYPE" \
    "Key=Product,Value=$PRODUCT" \
    "Key=Team,Value=$TEAM" \
    "Key=Service,Value=$SERVICE" \
    "Key=Owner,Value=$OWNER" \
    "Key=stack-role,Value=network" \
    --capabilities CAPABILITY_IAM)
    
    cf_response=$?

    if [ ! -z $ENABLE_VPC_PEERING ]; then 
        if [ $cf_response -eq 0 ];then
            # Once the stack is built, wait for it to be completed
            STACK_IDS=$(echo $STACK_OUTPUT | jq -r ".StackId")
            export STACK_IDS
            $LOCAL_PATH/wait-new-stack.sh
        else
            echo "Failed when attempting to initiate stack creation"
            echo $STACK_OUTPUT
            cf_response=212
        fi
    fi
    return $cf_response
}

network_template_generator --enable_ipv6 $ENABLE_IPV6
create_aws_network_stack