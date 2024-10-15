#!/bin/bash
#set -x #echo on

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh
[ -e $LOCAL_PATH/../clouds/oracle.sh ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT provided or found.  Exiting without creating stack."
    exit 204
fi

AZ_REGION="us-east-1"

#stack name ends up like: lonely-aaron-cname
[ -z "$STACK_NAME" ] && STACK_NAME="${ENVIRONMENT}-${UNIQUE_ID}-cname"

#Automated DNS entries in this zone

[ -z "$CNAME_DNS_ZONE_ID" ] && CNAME_DNS_ZONE_ID="$TOP_LEVEL_DNS_ZONE_ID"

[ -z "$CNAME_DNS_ZONE_DOMAIN_NAME" ] && CNAME_DNS_ZONE_DOMAIN_NAME="$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$ORACLE_CLOUD_NAME" ] && ORACLE_CLOUD_NAME="${ENVIRONMENT}-${ORACLE_REGION}"

if [ -z "$CNAME_TARGET" ]; then
    if [[ "$PUBLIC_FLAG" == "true" ]]; then
        CNAME_TARGET="${ORACLE_CLOUD_NAME}-${UNIQUE_ID}.$ORACLE_DNS_ZONE_NAME"
    else
        CNAME_TARGET="${ORACLE_CLOUD_NAME}-${UNIQUE_ID}-internal.$ORACLE_DNS_ZONE_NAME"
    fi
fi
[ -z "$CNAME_VALUE" ] && CNAME_VALUE="${UNIQUE_ID}"

CF_TEMPLATE_YAML="$LOCAL_PATH/../templates/oracle-cname.template"

describe_stack=$(aws cloudformation describe-stacks --region "$AZ_REGION" --stack-name "$STACK_NAME")
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

if [ "$CF_OPERATION" == "create-stack" ] || [ "$CF_OPERATION" == "update-stack" ] ; then
    STACK_TAGS=<<TILLEND
--tags "Key=Name,Value=$STACK_NAME"
"Key=Environment,Value=$ENVIRONMENT_TYPE" \
"Key=Product,Value=$PRODUCT" \
"Key=Team,Value=$TEAM" \
"Key=Service,Value=$SERVICE" \
"Key=Owner,Value=$OWNER" \
"Key=environment,Value=$ENVIRONMENT" \
"Key=stack-role,Value=oracle-cname"
TILLEND
else
    STACK_TAGS=
fi

STACK_OUTPUT=$(aws cloudformation $CF_OPERATION --region=$AZ_REGION --stack-name $STACK_NAME \
--template-body file://$CF_TEMPLATE_YAML \
--parameters ParameterKey=TagEnvironment,ParameterValue=$ENVIRONMENT \
ParameterKey=CNameTarget,ParameterValue=$CNAME_TARGET \
ParameterKey=CNameValue,ParameterValue=$CNAME_VALUE \
ParameterKey=HostedZoneId,ParameterValue=$CNAME_DNS_ZONE_ID \
ParameterKey=HostedZoneDomain,ParameterValue=$CNAME_DNS_ZONE_DOMAIN_NAME \
$STACK_TAGS \
--capabilities CAPABILITY_IAM 2>&1)

cf_response=$?

#can add the following to the above to make DNS dynamic by variable

if [ $cf_response -eq 0 ];then
    # Once the stack is built, wait for it to be completed
    STACK_IDS=$(echo $STACK_OUTPUT | jq -r ".StackId")
    export STACK_IDS
    
    CLOUD_NAME="us-east-1-peer1" $LOCAL_PATH/wait-new-stack.sh
    cf_response=$?
else
    if [[ "$CF_OPERATION" == "update-stack" ]]; then
        if [[ $cf_response -eq 255 ]] || [[ $cf_response -eq 254 ]]; then
            echo "$STACK_OUTPUT" | grep -q "No updates are to be performed"
            if [[ $? -eq 0 ]]; then
                echo "Stack not updated, no changes required"
                exit 0
            else
                echo "Error ($cf_response) in $CF_OPERATION operation: $STACK_OUTPUT"
                exit $cf_response
            fi
        fi
    fi
    echo "Failed when attempting to initiate stack creation"
    echo $STACK_OUTPUT
fi
exit $cf_response
