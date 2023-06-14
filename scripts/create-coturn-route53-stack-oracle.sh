#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh
[ -e $LOCAL_PATH/../clouds/oracle.sh ] && . $LOCAL_PATH/../clouds/oracle.sh

[ -e $LOCAL_PATH/hcvlib.sh ] && . $LOCAL_PATH/hcvlib.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#make sure we have a cloud prefix
[ -z $CLOUD_PREFIX ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX

[ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX="vaas"

[ -z $AZ_REGION ] && AZ_REGION=$EC2_REGION

[ -z $JVB_AZ_LETTER1 ] && JVB_AZ_LETTER1="a"
[ -z $JVB_AZ_LETTER2 ] && JVB_AZ_LETTER2="b"

# We need an envirnment "all"
if [ -z $ENVIRONMENT ]; then
  echo "No Environment provided or found.  Exiting without creating stack."
  exit 202
fi

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="$DOMAIN"
[ -z "$SERVICE" ] && SERVICE="jitsi-coturn"

# Use default domain
[ -z $TURN_DOMAIN ] && TURN_DOMAIN="jitsi.net"

# We need two SNS topics ARN identifiers, one for health checks and the other for autoscaling messages
if [ -z $COTURN_HEALTH_SNS ]; then
  echo "No COTURN_HEALTH_SNS provided or found.  Exiting without creating stack."
  exit 205
fi

#no AZ provided, so build one from the region and the shard number
if [ -z "$COTURN_AZ" ]; then
  COTURN_AZ="${AZ_REGION}${JVB_AZ_LETTER1},${AZ_REGION}${JVB_AZ_LETTER2}"
fi

#still have no AZ? not sure how but definitely fail
if [ -z "$COTURN_AZ" ]; then
  echo "No COTURN_AZ provided or found.  Exiting without creating stack."
  exit 204
fi

[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

[ -z "$REGION_ALIAS" ] && REGION_ALIAS=$AZ_REGION

#stack name ends up like: meet-jit-si-eu-west-3-aws1-coturn-oracle
[ -z "$STACK_NAME" ] && STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${CLOUD_PREFIX}-coturn-oracle"

#by defaut we use jitsi.net zone id
[ -z $DNS_ZONE_ID ] && DNS_ZONE_ID="ZJ6O8D5EJO64L"
[ -z $DNS_ZONE_DOMAIN_NAME ] && DNS_ZONE_DOMAIN_NAME='jitsi.net'

[ -z "$COTURN_DNS_ZONE_ID" ] && COTURN_DNS_ZONE_ID="ZJ6O8D5EJO64L"
[ -z "$COTURN_DNS_ZONE_DOMAIN_NAME" ] && COTURN_DNS_ZONE_DOMAIN_NAME="jitsi.net"

[ -z $TURN_DNS_NAME ] && TURN_DNS_NAME="${SHARD_BASE}-${REGION_ALIAS}-turnrelay-oracle.${TURN_DOMAIN}"
[ -z $TURN_DNS_ALIAS_NAME ] && TURN_DNS_ALIAS_NAME="${SHARD_BASE}-turnrelay-oracle.${TURN_DOMAIN}"

[ -z "$TURN_TCP_HEALTH_CHECKS" ] && TURN_TCP_HEALTH_CHECKS="false"

if [[ "$TURN_TCP_HEALTH_CHECKS" == "true" ]]; then
  TURN_TCP_FLAG="--turn_tcp"
fi

# Get Coturn instances public ips
# For this, first get the coturn instance pool id from the TF state file
# Then query for the public ips (as these are assigned at postinstall, they are not saved in the state file
export ORACLE_REGION
. $LOCAL_PATH/../terraform/coturn-state/get-coturn-state.sh

INSTANCES=$(oci --region $ORACLE_REGION compute-management instance-pool list-instances --instance-pool-id $COTURN_STATE_INSTANCE_POOL_ID --compartment-id $COTURN_STATE_COMPARTMENT_ID | jq -r ".data[].id")
for ID in $INSTANCES; do
  INSTANCE_PRIMARY_PUBLIC_IP=$(oci compute instance list-vnics --region $ORACLE_REGION --instance-id $ID | jq -r '.data[] | select(.["is-primary"] == true) | .["public-ip"]')
  if [ "$INSTANCE_PRIMARY_PUBLIC_IP" == "null" ]; then
    echo "All instances must have public ip assigned before creating route53 entries. Instance $ID does not have a public ip assigned."
    exit 210
  fi
  ORACLE_PUBLIC_IP_LIST="$ORACLE_PUBLIC_IP_LIST,$INSTANCE_PRIMARY_PUBLIC_IP"
done
ORACLE_PUBLIC_IP_LIST="${ORACLE_PUBLIC_IP_LIST:1}"

# Comma separated list e.g. 193.123.39.211,193.123.36.31
if [ -z "$ORACLE_PUBLIC_IP_LIST" ]; then
  echo "No ORACLE_PUBLIC_IP_LIST provided or found.  Exiting without creating stack."
  exit 206
fi

echo "Found the following COTURN public ips: $ORACLE_PUBLIC_IP_LIST"

#use the standard cloudformation template by default
[ -z $CF_TEMPLATE_JSON ] && CF_TEMPLATE_JSON="/tmp/vaas-coturn-{$REGION_ALIAS}.template.json"

check_cloudformation_stack_status ${AZ_REGION} ${STACK_NAME}

#check lambda function that custom templates use
[ -z "$COTURN_LAMBDA_FUNCTION_NAME" ] && COTURN_LAMBDA_FUNCTION_NAME="all-cf-update-route53"
check_lambda_function_status ${AZ_REGION} ${COTURN_LAMBDA_FUNCTION_NAME}

#clean current template
cat /dev/null >$CF_TEMPLATE_JSON

#generate new template
$LOCAL_PATH/../templates/create_coturn_route53_oracle_template.py --region $AZ_REGION --regionalias $REGION_ALIAS --filepath $CF_TEMPLATE_JSON \
  --oracle_public_ip_list "$ORACLE_PUBLIC_IP_LIST" $TURN_TCP_FLAG

STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
  --template-body file://$CF_TEMPLATE_JSON \
  --parameters ParameterKey=RegionAlias,ParameterValue=$REGION_ALIAS \
  ParameterKey=CoturnHealthAlarmSNS,ParameterValue=$COTURN_HEALTH_SNS \
  ParameterKey=CoturnLambdaFunctionName,ParameterValue=$COTURN_LAMBDA_FUNCTION_NAME \
  ParameterKey=DnsZoneID,ParameterValue=$COTURN_DNS_ZONE_ID \
  ParameterKey=TURNDnsName,ParameterValue=$TURN_DNS_NAME \
  ParameterKey=TURNDnsAliasName,ParameterValue=$TURN_DNS_ALIAS_NAME \
  ParameterKey=TagEnvironmentType,ParameterValue="$ENVIRONMENT_TYPE" \
  ParameterKey=TagProduct,ParameterValue="$PRODUCT" \
  ParameterKey=TagTeam,ParameterValue="$TEAM" \
  ParameterKey=TagOwner,ParameterValue="$OWNER" \
  ParameterKey=TagService,ParameterValue="$SERVICE" \
  ParameterKey=TagEnvironment,ParameterValue=$ENVIRONMENT \
  ParameterKey=TagDomainName,ParameterValue=$DOMAIN \
  ParameterKey=TagGitBranch,ParameterValue=$GIT_BRANCH \
  --tags "Key=Name,Value=$STACK_NAME" \
  "Key=Environment,Value=$ENVIRONMENT_TYPE" \
  "Key=Product,Value=$PRODUCT" \
  "Key=Team,Value=$TEAM" \
  "Key=Service,Value=$SERVICE" \
  "Key=Owner,Value=$OWNER" \
  "Key=environment,Value=$ENVIRONMENT" \
  "Key=stack-role,Value=coturn" \
  "Key=domain,Value=$DOMAIN" \
  --capabilities CAPABILITY_IAM)

if [ $? == 0 ]; then
  # Once the stack is built, wait for it to be completed
  STACK_IDS=$(echo $STACK_OUTPUT | jq -r ".StackId")
  export STACK_IDS
  export EC2_REGION
  $LOCAL_PATH/wait-new-stack.sh
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
