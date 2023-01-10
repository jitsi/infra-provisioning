#!/bin/bash
set -x
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="false"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

if [ -z "$SHARDS" ]; then
    if [ ! -z "$RELEASE_NUMBER" ]; then
        echo "No SHARDS set, searching for shards by release number $RELEASE_NUMBER"
        SHARDS=$(ENVIRONMENT="$ENVIRONMENT" DISPLAY="shards" RELEASE_NUMBER="$RELEASE_NUMBER" CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER)
    else
        echo "No RELEASE_NUMBER set, searching for all shards in environment"
        SHARDS=$(ENVIRONMENT="$ENVIRONMENT" DISPLAY="shards" CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER)
    fi
fi

if [ -z "$SHARDS" ]; then
    echo "No SHARDS found or set, exiting"
    exit 1
fi

FINAL_RET=0

#also supports disable action
[ -z "$ALARM_ACTION" ] && ALARM_ACTION="enable"

for SHARD in $SHARDS; do
    echo "enabling alarms on $SHARD"
    ALARM_ACTION="$ALARM_ACTION" SHARD="$SHARD" $LOCAL_PATH/update-shard-alarm.sh $ANSIBLE_SSH_USER
    if [ $? -gt 0 ]; then
        FINAL_RET=2
    fi
done

exit $FINAL_RET