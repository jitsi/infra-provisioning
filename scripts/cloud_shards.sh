#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

if [ -z "$CLOUD_NAME" ]; then
        echo "No CLOUD_NAME set, exiting"
        exit 2
fi

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
#  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
#  echo "Run ansible as $ANSIBLE_SSH_USER"
fi
. $LOCAL_PATH/../clouds/$CLOUD_NAME.sh

DATACENTERS="[\"$CLOUD_NAME\",\"$ENVIRONMENT-$ORACLE_REGION\"]"
OCI_DATACENTERS="$ENVIRONMENT-$ORACLE_REGION"
AWS_DATACENTERS="$CLOUD_NAME"

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="false"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

SHARDS=$(SERVICE="signal" DISPLAY="shards" OCI_DATACENTERS="$OCI_DATACENTERS" AWS_DATACENTERS="$AWS_DATACENTERS" DATACENTERS="$DATACENTERS" CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER)
#SHARDS=$($LOCAL_PATH/shard.py --list --region $EC2_REGION --environment $ENVIRONMENT $EXTRA_PARAMS)
if [ $? -eq 0 ]; then
        echo $SHARDS
        exit 0
else
        exit 0
fi
