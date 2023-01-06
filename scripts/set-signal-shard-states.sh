#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#load region defaults
[ -e $LOCAL_PATH/../regions/all.sh ] && . $LOCAL_PATH/../regions/all.sh

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

if [ -z "${SHARDS_READY}${SHARDS_DRAIN}" ]; then
    echo "Need to define SHARDS_READY and/or SHARDS_DRAIN"
    exit 1
fi

RET=0

## set file on shard to drain [new]
SHARD_READY_IPS=""
for SHARD in $SHARDS_READY; do
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $SHARD --environment $ENVIRONMENT)
    SHARD_IP=$($LOCAL_PATH/node.py --environment $ENVIRONMENT --shard $SHARD --role core --oracle --region $SHARD_REGION --batch)
    if [ -z $SHARD_IP ]; then
        echo "No SHARD_IP found from $SHARD, skipping"
        RET=2
    fi
    SHARD_READY_IPS="$SHARD_IP,$SHARD_READY_IPS"
done

SHARDS_DRAIN_IPS=""
for SHARD in $SHARDS_DRAIN; do
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $SHARD --environment $ENVIRONMENT)
    SHARD_IP=$($LOCAL_PATH/node.py --environment $ENVIRONMENT --shard $SHARD --role core --oracle --region $SHARD_REGION --batch)
    if [ -z $SHARD_IP ]; then
        echo "No SHARD_IP found from $SHARD, skipping"
        RET=2
    fi
    SHARD_DRAIN_IPS="$SHARD_IP,$SHARD_DRAIN_IPS"
done

cd $ANSIBLE_BUILD_PATH

if [ ! -z "$SHARD_READY_IPS" ]; then
    ansible-playbook ansible/set-signal-state.yml \
        -i "$SHARD_READY_IPS," \
        -e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
        -e "shard_state=ready"
fi

if [ ! -z "$SHARD_DRAIN_IPS" ]; then
    ansible-playbook ansible/set-signal-state.yml \
        -i "$SHARD_DRAIN_IPS," \
        -e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
        -e "shard_state=drain"
fi

cd -

OUT_RET=$?
# check for failures further up in the script, only exit cleanly if all steps were successful
if [ $RET -eq 0 ]; then
    exit $OUT_RET
else
    exit $RET
fi
