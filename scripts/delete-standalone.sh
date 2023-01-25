#!/bin/bash
set -x #echo on

#takes one parameter, the number of shards to create
#detects the appropriate next shard number and creates it

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="aws"
# default shard base
[ -z "$SHARD_BASE" ] && SHARD_BASE="$ENVIRONMENT"

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

[ -z "$DNS_ZONE_ID" ] && DNS_ZONE_ID="$TOP_LEVEL_DNS_ZONE_ID"
[ -z "$DNS_ZONE_DOMAIN_NAME" ] && DNS_ZONE_DOMAIN_NAME="$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$UNIQUE_ID" ] && UNIQUE_ID="$TEST_ID"

if [[ "$CLOUD_PROVIDER" == "aws" ]]; then

    #default cloud from basic defaults
    [ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

    [ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh"

    #region defaults
    [ -z "$EC2_REGION" ] && EC2_REGION=$DEFAULT_EC2_REGION

    [ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION
    #make sure we have a cloud prefix
    [ -z "$CLOUD_PREFIX" ] && CLOUD_PREFIX=$DEFAULT_CLOUD_PREFIX


    #error out if test id is not provided
    if [ -z "$STACK_NAME" ]; then
        if [ -z "$UNIQUE_ID" ]; then
            if [ -z "$1" ]; then
                echo "No STACK_NAME or UNIQUE_ID provided, exiting..."
                exit 1
            else
                UNIQUE_ID="$1"
            fi
        fi
    fi

    #stack name ends up like instance name if not provided
    [ -z "$STACK_NAME" ] && STACK_NAME="${SHARD_BASE}-${REGION_ALIAS}-${UNIQUE_ID}"

    echo "Lookuping up details for stack $STACK_NAME in region $EC2_REGION"
    describe_stack=$(aws cloudformation describe-stacks --region "$EC2_REGION" --stack-name "$STACK_NAME" 2>&1)
    FINAL_RET=$?
    if [ $FINAL_RET -eq 0 ]; then
        #found the stack
        #lookup current public DNS entry
        STACK_PUBLIC_DNS=$(echo $describe_stack|jq -r '.Stacks[0].Outputs[]|select(.OutputKey=="PublicDNSRecord")|.OutputValue')
        #now delete it
        echo "Deleting stack $STACK_NAME in region $EC2_REGION"
        aws cloudformation delete-stack --region=$EC2_REGION --stack-name="$STACK_NAME"
        if [ $? -eq 0 ]; then
            aws cloudformation wait stack-delete-complete --region "$EC2_REGION" --stack-name "$STACK_NAME"
            if [ $? -eq 0 ]; then
                echo "Stack $STACK_NAME in $EC2_REGION delete complete."
                if [ ! -z "$STACK_PUBLIC_DNS" ]; then
                    # check and delete Route53 record if found
                    echo "Searching for leftover DNS record for $STACK_PUBLIC_DNS"
                    RECORD=$(aws route53 list-resource-record-sets --hosted-zone-id $DNS_ZONE_ID --query "ResourceRecordSets[?Name == '$STACK_PUBLIC_DNS.']|[?Type == 'A']|[0]")
                    if [ $? -eq 0 ]; then
                        if [[ "$RECORD" == "null" ]]; then
                            echo "No record found for $DNS_ZONE_ID DNS $STACK_PUBLIC_DNS, no more cleanup required"
                            exit 0
                        else
                            echo "Attempting to delete record $STACK_PUBLIC_DNS from zone $DNS_ZONE_ID"
                            CHANGE_SET="{\"Changes\":[{\"Action\":\"DELETE\", \"ResourceRecordSet\":$RECORD}]}"
                            aws route53 change-resource-record-sets --hosted-zone-id $DNS_ZONE_ID  --change-batch "$CHANGE_SET"
                            FINAL_RET=$?
                            if [[ $FINAL_RET -eq 0 ]]; then
                                echo "Record deleted successfully"
                            else
                                echo "Delete of DNS failed"
                                echo $FINAL_RET
                            fi
                        fi
                    else
                        echo "Failed looking up DNS records for $STACK_NAME $STACK_PUBLIC_DNS, skipping further cleanup. $RECORD"
                        FINAL_RET=100
                    fi
                else
                    echo "No public DNS found for stack, skipping DNS cleanup"
                fi
            else
                echo "Failed deleting stack $STACK_NAME in $EC2_REGION, see AWS console for more information"
                FINAL_RET=101
            fi
        else        
            echo "DELETE FAILED: Stack with name $STACK_NAME in region $EC2_REGION, skipping further steps"
        fi
    else
        echo "No stack found with name $STACK_NAME in region $EC2_REGION"
        echo $describe_stack
    fi
fi

if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then

    #load cloud defaults
    [ -e $LOCAL_PATH/../clouds/oracle.sh ] && . $LOCAL_PATH/../clouds/oracle.sh

    if [ -z "$UNIQUE_ID" ]; then
        if [ -z "$1" ]; then
            echo "No STACK_NAME or UNIQUE_ID provided, exiting..."
            exit 1
        else
            UNIQUE_ID="$1"
        fi
    fi
    if [ -z "$ORACLE_REGION" ]; then
        echo "No ORACLE_REGION provided, exiting..."
        exit 1
    fi

    UNIQUE_ID=$UNIQUE_ID $LOCAL_PATH/../terraform/standalone/delete-standalone-server-oracle.sh
    FINAL_RET=$?
fi

exit $FINAL_RET