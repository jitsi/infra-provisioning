#!/bin/bash
set -x #echo on

#IF THIS APPLICATION IS SYMLINKED AS create-app-shard-stack-<CMD_SHARD_NUMBER>.sh
#WE DETECT THIS AND CAN USE THIS AS THE DEFAULT SHARD NUMBER IF IT IS NOT PROVIDED
CMD_SHARD_NUMBER=$(echo "$0" | cut -d'-' -f5 | cut -d'.' -f1)

#echo "CMD SHARD $CMD_SHARD_NUMBER"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#Look for JVB counts by region in current directory
JVB_COUNT_FILE="./jvb-count-by-region"

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

#default cloud from basic defaults
[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh"

#make sure we have a cloud prefix
[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX

[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"

#region defaults
[ -z "$EC2_REGION" ] && EC2_REGION=$DEFAULT_EC2_REGION

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION

[ -z "$JVB_AZ_REGION" ] && JVB_AZ_REGION=$EC2_REGION

[ -z "$JVB_AZ_LETTER1" ] && JVB_AZ_LETTER1="a"
[ -z "$JVB_AZ_LETTER2" ] && JVB_AZ_LETTER2="b"

# Dont use a JVB elp pool if don't have it or skip it
if [ -z "$USE_JVB_EIP_POOL" ] || [ "$USE_JVB_EIP_POOL" == "false" ]; then
    JVB_EIP_POOL="false"
elif [ "$USE_JVB_EIP_POOL" == 'true' ]; then
    if [ -z "$JVB_EIP_POOL" ]; then
        echo "No JVB EIPs Pool provided or found.  Exiting without creating stack."
        exit 201
    fi
fi

[ -z "$PULL_NETWORK_STACK" ]  &&  PULL_NETWORK_STACK="true"

[ -z "$ENABLE_PAGERDUTY_ALARMS" ] && ENABLE_PAGERDUTY_ALARMS="false"

[ -z "$SHARD_CREATE_OUTPUT_FILE" ] && SHARD_CREATE_OUTPUT_FILE="../../../test-results/shard_create_output.txt"

#ensure that shard create output file directory exists
OUTPUT_FILE_DIR=$(dirname $SHARD_CREATE_OUTPUT_FILE);
[ ! -d $OUTPUT_FILE_DIR ] && mkdir -p $OUTPUT_FILE_DIR

# We need a shard number, so either detect it or fail
if [ -z "$SHARD_NUMBER" ]; then
    if [ ! -z "$CMD_SHARD_NUMBER" ]; then
        SHARD_NUMBER="$CMD_SHARD_NUMBER"
    else
        echo "No SHARD_NUMBER provided or found.  Exiting without creating stack."
        exit 200
    fi
fi

# We need a name of the environment (like jitsi-net)
if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT provided or found.  Exiting without creating stack."
    exit 202
fi

# We need an xmpp and http domain (like jitsi.net)
if [ -z "$DOMAIN" ]; then
    echo "No DOMAIN provided or found.  Exiting without creating stack."
    exit 203
fi

# We need two SNS topics ARN identifiers, one for health checks and the other for autoscaling messages
if [ -z "$JVB_HEALTH_SNS" ]; then
    echo "No JVB_HEALTH_SNS provided or found.  Exiting without creating stack."
    exit 205
fi
if [ -z "$JVB_ASG_SNS" ]; then
    echo "No JVB_ASG_SNS provided or found.  Exiting without creating stack."
    exit 206
fi

#no AZ provided, so build one from the region and the shard number
if [ -z "$JVB_AZ" ]; then
    if [ $((SHARD_NUMBER%2)) -eq 0 ]; then
        #even shard number goes in the 1st AZ (us-east-1a)
        JVB_AZ="${JVB_AZ_REGION}${JVB_AZ_LETTER1}"
    else
        #odd shard number goes in the 2nd AZ (us-east-1b)
        JVB_AZ="${JVB_AZ_REGION}${JVB_AZ_LETTER2}"
    fi
fi

#still have no AZ? not sure how but definitely fail
if [ -z "$JVB_AZ" ]; then
    echo "No JVB_AZ provided or found.  Exiting without creating stack."
    exit 204
fi

JVB_AZ_LETTER="${JVB_AZ: -1}"

#eval DEFAULT_PUBLIC_SUBNET_ID=\$DEFAULT_PUBLIC_SUBNET_ID_${JVB_AZ_LETTER}
#eval DEFAULT_DC_SUBNET_IDS=\$DEFAULT_DC_SUBNET_IDS_${JVB_AZ_LETTER}


[ -z "$JVB_ASSOCIATE_PUBLIC_IP" ] && JVB_ASSOCIATE_PUBLIC_IP="false"


#if we're not given versions, search for the latest of each type of image
[ -z "$JVB_VERSION" ] && JVB_VERSION='latest'

[ -z "$SIGNAL_VERSION" ] && [ ! -z "$JICOFO_VERSION" ] && [ ! -z "$JITSI_MEET_VERSION" ] && SIGNAL_VERSION="${JICOFO_VERSION}-${JITSI_MEET_VERSION}"
[ -z "$SIGNAL_VERSION" ] && SIGNAL_VERSION='latest'

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER=0



#Default shard base name to environment name
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

#shard name ends up like: enso-aws1-us-east-1-s0
[ -z "$SHARD_NAME" ] && SHARD_NAME="${SHARD_BASE}-${REGION_ALIAS}${JVB_AZ_LETTER}-s${SHARD_NUMBER}"

#stack name ends up like: enso-aws1-us-east-1-s0
[ -z "$STACK_NAME" ] && STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}${JVB_AZ_LETTER}-s${SHARD_NUMBER}"

#default ssh key for initial EC2 login
[ -z "$EC2_KEY_NAME" ] && EC2_KEY_NAME="video"

#Automated DNS entries in this zone
[ -z "$DNS_ZONE_ID" ] && DNS_ZONE_ID="ZP3DAJR109E5U"
[ -z "$DNS_ZONE_DOMAIN_NAME" ] && DNS_ZONE_DOMAIN_NAME="infra.jitsi.net"

#Public Domain is deprecated and defaults to domain
[ -z "$PUBLIC_DOMAIN" ] && PUBLIC_DOMAIN=$DOMAIN

#pagerduty SNS topic, created in the network CF stack
[ -z "$PAGERDUTY_SNSTOPICNAME" ] && PAGERDUTY_SNSTOPICNAME="PagerDutyAlarms"

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="$DOMAIN"
[ -z "$SERVICE" ] && SERVICE="jitsi-meet"


#EC2 instance parameters

[ -z "$APP_INSTANCE_TYPE" ] && APP_INSTANCE_TYPE="$DEFAULT_APP_INSTANCE_TYPE"
[ -z "$APP_INSTANCE_TYPE" ] && APP_INSTANCE_TYPE="t3.large"

APP_INSTANCE_FAMILY="$(echo $APP_INSTANCE_TYPE|cut -d'.' -f1)"

FINAL_CHAR="${APP_INSTANCE_FAMILY: -1}"
if [[ "$FINAL_CHAR" == "g" ]]; then
    APP_TARGET_ARCHITECTURE="arm64"
else
    APP_TARGET_ARCHITECTURE="x86_64"
fi

if [ -z "$ENABLE_EC2_RECOVERY" ]; then
    case $APP_INSTANCE_FAMILY in
        z1d)
            ENABLE_EC2_RECOVERY="false"
            ;;
        *)
            ENABLE_EC2_RECOVERY="true"
            ;;
    esac

fi

[ -z "$JVB_INSTANCE_TYPE" ] && JVB_INSTANCE_TYPE="$DEFAULT_JVB_INSTANCE_TYPE"
[ -z "$JVB_INSTANCE_TYPE" ] && JVB_INSTANCE_TYPE="t3.large"

JVB_INSTANCE_FAMILY="$(echo $JVB_INSTANCE_TYPE|cut -d'.' -f1)"

FINAL_CHAR="${JVB_INSTANCE_FAMILY: -1}"
if [[ "$FINAL_CHAR" == "g" ]]; then
    JVB_TARGET_ARCHITECTURE="arm64"
else
    JVB_TARGET_ARCHITECTURE="x86_64"
fi

[ -z "$JVB_PLACEMENT_TENANCY" ] && JVB_PLACEMENT_TENANCY="default"

[ -z "$APP_VIRT_TYPE" ] && APP_VIRT_TYPE="HVM"
[ -z "$JVB_VIRT_TYPE" ] && JVB_VIRT_TYPE="HVM"

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="aws"

# whether to create JVBs in AWS or not
if [ -z "$ENABLE_JVB_ASG" ]; then
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
        ENABLE_JVB_ASG="true"
    else
        ENABLE_JVB_ASG="false"
    fi
fi

if [ -z "$ENABLE_ALARM_SNS_ON_CREATE" ]; then
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
        ENABLE_ALARM_SNS_ON_CREATE="true"
    else
        ENABLE_ALARM_SNS_ON_CREATE="false"
    fi
fi

if [ -z "$JVB_MIN_COUNT" ] && [ -f "$JVB_COUNT_FILE" ]; then
    # check if JVB count by region is defined, if so use it
    REGION_JVB_MIN_COUNT=$(cat $JVB_COUNT_FILE | grep $AZ_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
    [ ! -z "$REGION_JVB_MIN_COUNT" ] && JVB_MIN_COUNT="$REGION_JVB_MIN_COUNT"
fi

if [ -z "$JVB_DESIRED_COUNT" ] && [ -f "$JVB_COUNT_FILE" ]; then
    # check if JVB count by region is defined, if so use it
    REGION_JVB_DESIRED_COUNT=$(cat $JVB_COUNT_FILE | grep $AZ_REGION | awk 'BEGIN { FS = "|" } ; {print $3}')
    [ ! -z "$REGION_JVB_DESIRED_COUNT" ] && JVB_DESIRED_COUNT="$REGION_JVB_DESIRED_COUNT"
fi

if [ -z "$JVB_MAX_COUNT" ] && [ -f "$JVB_COUNT_FILE" ]; then
    # check if JVB count by region is defined, if so use it
    REGION_JVB_MAX_COUNT=$(cat $JVB_COUNT_FILE | grep $AZ_REGION | awk 'BEGIN { FS = "|" } ; {print $4}')
    [ ! -z "$REGION_JVB_MAX_COUNT" ] && JVB_MAX_COUNT="$REGION_JVB_MAX_COUNT"
fi

[ -z "$JVB_MIN_COUNT" ] && JVB_MIN_COUNT="$JVB_DEFAULT_MIN_COUNT"
[ -z "$JVB_MAX_COUNT" ] && JVB_MAX_COUNT="$JVB_DEFAULT_MAX_COUNT"
[ -z "$JVB_DESIRED_COUNT" ] && JVB_DESIRED_COUNT="$JVB_DEFAULT_DESIRED_COUNT"

[ -z "$JVB_MIN_COUNT" ] && JVB_MIN_COUNT=2
[ -z "$JVB_MAX_COUNT" ] && JVB_MAX_COUNT=8
[ -z "$JVB_DESIRED_COUNT" ] && JVB_DESIRED_COUNT="$JVB_MIN_COUNT"

[ -z "$SIGNAL_IMAGE_ID" ] && SIGNAL_IMAGE_ID=$($LOCAL_PATH/ami.py --batch --type=Signal --version="$SIGNAL_VERSION" --region="$EC2_REGION" --architecture $APP_TARGET_ARCHITECTURE)

#No image was found, probably not built yet?

if [[ "$ENABLE_JVB_ASG" == "true" ]]; then
    #Look up images based on version, or default to latest
    [ -z "$JVB_IMAGE_ID" ] && JVB_IMAGE_ID=$($LOCAL_PATH/ami.py --batch --type=JVB --version="$JVB_VERSION" --region="$EC2_REGION" --architecture $JVB_TARGET_ARCHITECTURE)
    if [ -z "$JVB_IMAGE_ID" ]; then
        echo "No JVB_IMAGE_ID provided or found.  Exiting without creating stack."
        exit 210
    fi
else
    JVB_IMAGE_ID="skip"
fi

if [ -z "$SIGNAL_IMAGE_ID" ]; then
    echo "No SIGNAL_IMAGE_ID provided or found. Exiting without creating stack."
    exit 211
fi

#assume no datadog if not specified
[ -z "$DATADOG_ENABLED" ] && DATADOG_ENABLED="false"

#check lambda function that custom templates use
[ -z "$APP_LAMBDA_FUNCTION_NAME" ] && APP_LAMBDA_FUNCTION_NAME="all-cf-update-route53"

describe_lambda_functions=$(aws lambda list-functions --region "$EC2_REGION" | jq -r .Functions[].FunctionArn | grep -q $APP_LAMBDA_FUNCTION_NAME)
if [ $? -eq 0 ]; then
    echo "Function exists. Continue creation CF stack."
else   
    echo "Function not found. Deploy function $APP_LAMBDA_FUNCTION_NAME into region before CF stack creation."
    exit 212    
fi

if [ -z "$CF_TEMPLATE_JSON" ]; then 
    #Use the standard cloudformation template by default
    CF_TEMPLATE_JSON="/tmp/vaas-app-shard-tmp-$STACK_NAME.template.json"
fi

[ -z "$GIT_BRANCH" ] && GIT_BRANCH="master"

describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_NAME")
if [ $? -eq 0 ]; then
    echo "App stack exists. We should remove it manually."
    exit 213
else
    CF_OPERATION='create-stack'
fi

#clean current template
cat /dev/null > $CF_TEMPLATE_JSON

#generate new template
$LOCAL_PATH/../templates/create_app_shard_template.py --region "$EC2_REGION" --regionalias "$REGION_ALIAS" --stackprefix "$CLOUD_PREFIX" \
--az_letter "$JVB_AZ_LETTER" --filepath "$CF_TEMPLATE_JSON" --pull_network_stack "$PULL_NETWORK_STACK" \
--enable_pagerduty_alarms "$ENABLE_PAGERDUTY_ALARMS" --release_number "$RELEASE_NUMBER" --enable_ec2_recovery "$ENABLE_EC2_RECOVERY" \
--enable_jvb_asg "$ENABLE_JVB_ASG" --enable_alarm_sns_on_create "$ENABLE_ALARM_SNS_ON_CREATE"

aws cloudformation $CF_OPERATION --region="$EC2_REGION" --stack-name "$STACK_NAME" \
--template-body file://"$CF_TEMPLATE_JSON" \
--parameters ParameterKey=KeyName,ParameterValue="$EC2_KEY_NAME" \
ParameterKey=DomainName,ParameterValue="$DNS_ZONE_DOMAIN_NAME" \
ParameterKey=StackNamePrefix,ParameterValue="$CLOUD_PREFIX" \
ParameterKey=RegionAlias,ParameterValue="$REGION_ALIAS" \
ParameterKey=ShardId,ParameterValue="$SHARD_NUMBER" \
ParameterKey=JVBImageId,ParameterValue="$JVB_IMAGE_ID" \
ParameterKey=JVBAvailabilityZoneLetter,ParameterValue="$JVB_AZ_LETTER" \
ParameterKey=JVBAvailabilityZone,ParameterValue="$JVB_AZ" \
ParameterKey=SignalImageId,ParameterValue="$SIGNAL_IMAGE_ID" \
ParameterKey=PublicDNSHostedZoneId,ParameterValue="$DNS_ZONE_ID" \
ParameterKey=JVBAssociatePublicIpAddress,ParameterValue="$JVB_ASSOCIATE_PUBLIC_IP" \
ParameterKey=JVBHealthAlarmSNS,ParameterValue="$JVB_HEALTH_SNS" \
ParameterKey=JVBASGAlarmSNS,ParameterValue="$JVB_ASG_SNS" \
ParameterKey=PagerDutySNSTopicName,ParameterValue="$PAGERDUTY_SNSTOPICNAME" \
ParameterKey=AppInstanceType,ParameterValue="$APP_INSTANCE_TYPE" \
ParameterKey=AppInstanceVirtualization,ParameterValue="$APP_VIRT_TYPE" \
ParameterKey=AppLambdaFunctionName,ParameterValue="$APP_LAMBDA_FUNCTION_NAME" \
ParameterKey=JVBInstanceType,ParameterValue="$JVB_INSTANCE_TYPE" \
ParameterKey=JVBPlacementTenancy,ParameterValue="$JVB_PLACEMENT_TENANCY" \
ParameterKey=JVBInstanceVirtualization,ParameterValue="$JVB_VIRT_TYPE" \
ParameterKey=JVBEIPPool,ParameterValue="\"$JVB_EIP_POOL\"" \
ParameterKey=JVBMinCount,ParameterValue="$JVB_MIN_COUNT" \
ParameterKey=JVBMaxCount,ParameterValue="$JVB_MAX_COUNT" \
ParameterKey=JVBDesiredCount,ParameterValue="$JVB_DESIRED_COUNT" \
ParameterKey=DatadogEnabled,ParameterValue="$DATADOG_ENABLED" \
ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
ParameterKey=TagTeam,ParameterValue="$TEAM" \
ParameterKey=TagOwner,ParameterValue="$OWNER" \
ParameterKey=TagService,ParameterValue="$SERVICE" \
ParameterKey=TagEnvironment,ParameterValue="$ENVIRONMENT" \
ParameterKey=TagPublicDomainName,ParameterValue="$PUBLIC_DOMAIN" \
ParameterKey=TagDomainName,ParameterValue="$DOMAIN" \
ParameterKey=TagShard,ParameterValue="$SHARD_NAME" \
ParameterKey=TagGitBranch,ParameterValue="$GIT_BRANCH" \
ParameterKey=TagCloudName,ParameterValue="$CLOUD_NAME" \
ParameterKey=TagCloudProvider,ParameterValue="$CLOUD_PROVIDER" \
--tags "Key=Name,Value=$SHARD_NAME" \
"Key=Environment,Value=$ENVIRONMENT_TYPE" \
"Key=Product,Value=$PRODUCT" \
"Key=Team,Value=$TEAM" \
"Key=Service,Value=$SERVICE" \
"Key=Owner,Value=$OWNER" \
"Key=environment,Value=$ENVIRONMENT" \
"Key=shard,Value=$SHARD_NAME" \
"Key=cloud_provider,Value=$CLOUD_PROVIDER" \
"Key=domain,Value=$DNS_ZONE_DOMAIN_NAME" \
"Key=stack-role,Value=shard" \
"Key=release_number,Value=\"$RELEASE_NUMBER\"" \
--capabilities CAPABILITY_IAM >> $SHARD_CREATE_OUTPUT_FILE
exit $?
