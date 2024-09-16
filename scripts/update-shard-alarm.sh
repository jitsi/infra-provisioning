#!/bin/bash
set -x

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi


if [ -z "$SHARD" ]; then
    echo "No shard name provided, exiting..."
    exit 1
fi

SHARD_PROVIDER=$($LOCAL_PATH/shard.sh core_provider $ANSIBLE_SSH_USER)

# in case of nomad shards, oracle alarms are created so treat them like oracle shards
if [[ "$SHARD_PROVIDER" == "nomad" ]]; then
    echo "No shard alarms for nomad shards, exiting..."
    exit 0
fi

SHARD_REGION=$(SHARD="$SHARD" $LOCAL_PATH/shard.sh shard_region $ANSIBLE_SSH_USER)

case "$SHARD_PROVIDER" in
    'aws')
        . $LOCAL_PATH/../regions/$SHARD_REGION.sh

        [ -z "$REGION_ALIAS" ] && REGION_ALIAS="$SHARD_REGION"

        [ -z "$ALARM_ACTION" ] && ALARM_ACTION="enable"

        if [ "$ALARM_ACTION" == "disable" ]; then
            CW_ACTION="disable-alarm-actions"
        else
            CW_ACTION="enable-alarm-actions"
        fi

        # region is always us-east, as that's where route53 metrics are written, so the there the alarms must reside
        ALARM_REGION="us-east-1"

        # lookup alarm from shard
        ALARM_NAME=$(aws cloudwatch describe-alarms --region $ALARM_REGION --alarm-name-prefix "$SHARD-$REGION_ALIAS-Route53XMPPHealthCheckFailedAlarm" | jq  -r '.MetricAlarms[].AlarmName')
        if [ $? -eq 0 ]; then
            if [ -z "$ALARM_NAME" ]; then
                echo "No alarm found matching $SHARD, exiting..."
                exit 2
            fi
            echo "Updating shard $SHARD to $ALARM_ACTION actions on alarm $ALARM_NAME"
            aws cloudwatch $CW_ACTION --region $ALARM_REGION --alarm-names $ALARM_NAME
            exit $?
        else
            echo "Error searching for alarm, exiting...."
            exit 3
        fi
        ;;
    'oracle')
        if [ "$ALARM_ACTION" == "disable" ]; then
            ALARM_ENABLED_FLAG="false"
        else
            ALARM_ENABLED_FLAG="true"
        fi

        ANY_RET=0
        EMAIL_RET=0
        . $LOCAL_PATH/../regions/$SHARD_REGION-oracle.sh
        ALARM_NAME="$SHARD-HealthAlarm"
        EMAIL_ALARM=$(oci monitoring alarm list --compartment-id $COMPARTMENT_OCID --region $SHARD_REGION --display-name "$ALARM_NAME" | jq -r ".data[]|select(.\"display-name\"==\"$ALARM_NAME\")|.id")
        if [[ ! -z "$EMAIL_ALARM" ]] && [[ "$EMAIL_ALARM" != "null" ]]; then
            for ALARM_ID in $EMAIL_ALARM; do
                oci monitoring alarm update --is-enabled $ALARM_ENABLED_FLAG --alarm-id $ALARM_ID --region $SHARD_REGION
                if [[ $? -gt 0 ]]; then
                    EMAIL_RET=2
                fi
            done
        else
            echo "No full failure alarm found for $SHARD in $SHARD_REGION compartment $COMPARTMENT_OCID"
            EMAIL_RET=5
        fi

        ALARM_NAME="$SHARD-HealthAnyAlarm"
        ANY_ALARM=$(oci monitoring alarm list --compartment-id $COMPARTMENT_OCID --region $SHARD_REGION --display-name "$ALARM_NAME" | jq -r ".data[]|select(.\"display-name\"==\"$ALARM_NAME\")|.id")
        if [[ ! -z "$ANY_ALARM" ]] && [[ "$ANY_ALARM" != "null" ]]; then
            for ALARM_ID in $ANY_ALARM; do
                oci monitoring alarm update --is-enabled $ALARM_ENABLED_FLAG --alarm-id $ALARM_ID --region $SHARD_REGION
                if [[ $? -gt 0 ]]; then
                    ANY_RET=2
                fi
            done
        else
            echo "No any failure alarm found for $SHARD in $SHARD_REGION compartment $COMPARTMENT_OCID"
            ANY_RET=5
        fi

        #TODO: actually implement shard alarms
        if [[ $ANY_RET -gt 0 ]] || [[ $EMAIL_RET -gt 0 ]]; then
            echo "Shard alarm update error for $SHARD in $SHARD_REGION compartment $COMPARTMENT_OCID"
            exit 5
        fi
        echo "Shard alarms enabled flag set to $ALARM_ENABLED_FLAG for $SHARD in $SHARD_REGION compartment $COMPARTMENT_OCID"
        exit 0
    ;;
    *)
        echo "unknown provider $SHARD_PROVIDER"
    ;;
esac
