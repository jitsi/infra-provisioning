#!/bin/bash
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# source cloud defaults
. "$LOCAL_PATH/../clouds/all.sh"

[ -z "$DNS_ZONE_ID" ] && DNS_ZONE_ID="$CLOUD_DNS_ZONE_ID"
[ -z "$DNS_ZONE_DOMAIN_NAME" ] && DNS_ZONE_DOMAIN_NAME="$CLOUD_DNS_ZONE_NAME"
[ -z "$DNS_RECORD_PREFIX" ] && DNS_RECORD_PREFIX="$SHARD_BASE"
[ -z "$DNS_REGION_SUFFIX" ] && DNS_REGION_SUFFIX="latency"
[ -z "$ALB_NAME" ] && ALB_NAME="${SHARD_BASE}-haproxy-ALB"

[ -z "$REGION_RECORD_NAME" ] && REGION_RECORD_NAME="$DNS_RECORD_PREFIX-$DNS_REGION_SUFFIX.$DNS_ZONE_DOMAIN_NAME"


if [ -z "$CLOUD_NAME" ]; then
    echo "No CLOUD_NAME set, exiting"
    exit 2
fi

[ -z "$RECORD_ACTION" ] && RECORD_ACTION=$1

if [ -z "$RECORD_ACTION" ]; then
    echo "No RECORD_ACTION set or passed as first parameter, exiting"
    exit 2
fi

case "$RECORD_ACTION" in

  "drain")
    CREATE_RECORD=false
    DELETE_RECORD=true
    ;;

  "ready")
    CREATE_RECORD=true
    DELETE_RECORD=false
    ;;

  "check")
    CREATE_RECORD=false
    DELETE_RECORD=false
    ;;

  *)
    echo "Action not supported: $RECORD_ACTION"
    exit 3
    ;;
esac

. "$LOCAL_PATH/../clouds/$CLOUD_NAME.sh"

set -x

export AWS_DEFAULT_REGION=$EC2_REGION

RECORD=$(aws route53 list-resource-record-sets --hosted-zone-id $DNS_ZONE_ID --query "ResourceRecordSets[?Name == '$REGION_RECORD_NAME.']|[?Type == 'AAAA']|[?Region=='$EC2_REGION']|[0]")

if [ $? -eq 0 ]; then

    if [[ "$RECORD" == "null" ]]; then
        echo "No record found for $ENVIRONMENT DNS $REGION_RECORD_NAME in region $EC2_REGION"
        if $DELETE_RECORD; then
            echo "Record already missing so doing nothing for record $REGION_RECORD_NAME for region $EC2_REGION"
        fi
        if $CREATE_RECORD; then
            echo "Attempting to create missing record $REGION_RECORD_NAME for region $EC2_REGION, searching for ALB"
            # find elb in region for environment
            ALB=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME']|[0]" --region $EC2_REGION)
            if [[ "$ALB" == "null" ]]; then
                echo "ALB not found $ALB_NAME in region $EC2_REGION"
                exit 5
            else
                ALB_TARGET="dualstack.$(echo $ALB | jq -r '.DNSName')"
                ALB_ZONE="$(echo $ALB | jq -r '.CanonicalHostedZoneId')"
                echo "Creating record with target $ALB_TARGET zone $ALB_ZONE"
                NEW_RECORD="{\"Name\":\"$REGION_RECORD_NAME.\", \"Type\":\"AAAA\", \"SetIdentifier\": \"$ENVIRONMENT $EC2_REGION ALB 0\", \"Region\":\"$EC2_REGION\",\"AliasTarget\":{\"HostedZoneId\":\"$ALB_ZONE\", \"DNSName\":\"$ALB_TARGET\", \"EvaluateTargetHealth\": true}}"
                # create new record like:
                ##
                # {
                #     "Name": "meet-jit-si-latency.cloud.jitsi.net.",
                #     "Type": "AAAA",
                #     "SetIdentifier": "meet-jit-si us-west-2 ALB 0",
                #     "Region": "us-west-2",
                #     "AliasTarget": {
                #         "HostedZoneId": "Z1H1FL5HABSF5",
                #         "DNSName": "dualstack.meet-jit-si-haproxy-alb-414503420.us-west-2.elb.amazonaws.com.",
                #         "EvaluateTargetHealth": true
                #     }
                # }
                echo $NEW_RECORD
                CHANGE_SET="{\"Changes\":[{\"Action\":\"CREATE\", \"ResourceRecordSet\":$NEW_RECORD}]}"
                aws route53 change-resource-record-sets --hosted-zone-id $DNS_ZONE_ID  --change-batch "$CHANGE_SET" --region $EC2_REGION
                FINAL_RET=$?
                if [[ $FINAL_RET -eq 0 ]]; then
                    echo "Record created successfully"
                    exit 0
                else
                    echo "Creation failed"
                    echo $FINAL_RET
                fi


            fi
        fi
    else
        RECORD="$(echo "$RECORD" | jq -c '.')"
        echo "record found for $ENVIRONMENT DNS $REGION_RECORD_NAME in region $EC2_REGION"
        echo $RECORD

        if $CREATE_RECORD; then
            echo "Record already existing so doing nothing on $REGION_RECORD_NAME for region $EC2_REGION"
        fi
        if $DELETE_RECORD; then
            echo "Attempting to delete record $REGION_RECORD_NAME for region $EC2_REGION"
            CHANGE_SET="{\"Changes\":[{\"Action\":\"DELETE\", \"ResourceRecordSet\":$RECORD}]}"
            aws route53 change-resource-record-sets --hosted-zone-id $DNS_ZONE_ID  --change-batch "$CHANGE_SET"
            FINAL_RET=$?
            if [[ $FINAL_RET -eq 0 ]]; then
                echo "Record deleted successfully"
                exit 0
            else
                echo "Delete failed"
                echo $FINAL_RET
            fi
        fi
    fi
fi