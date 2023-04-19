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
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

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

[ -z "$CONSUL_SHARD_STATES" ] && CONSUL_SHARD_STATES="true"

function consul_shard_state() {
    S=$1
    STATE=$2
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $S --environment $ENVIRONMENT)

    # improvement: iterate over datacenters and always go to local region

    CONSUL_URL="https://$ENVIRONMENT-$SHARD_REGION-consul.$TOP_LEVEL_DNS_ZONE_NAME/v1/kv/shard-states/$ENVIRONMENT/$SHARD"
    curl -X PUT -d "$STATE" $CONSUL_URL
    return $?
}

if [[ "$CONSUL_SHARD_STATES" == "true" ]]; then
    for SHARD in $SHARDS_READY; do
        consul_shard_state $SHARD 'ready'
        SRET=$?
        if [[ $SRET -gt 0 ]]; then
            RET=$SRET
        fi
    done
    for SHARD in $SHARDS_DRAIN; do
        consul_shard_state $SHARD 'drain'
        SRET=$?
        if [[ $SRET -gt 0 ]]; then
            RET=$SRET
        fi
    done
    if [[ "$CONSUL_SHARD_STATES_ONLY" == "true" ]]; then
        exit $RET
    fi
fi

## set file on shard to drain [new]
SHARD_READY_IPS=""
for SHARD in $SHARDS_READY; do
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $SHARD --environment $ENVIRONMENT)
    SHARD_IP=$($LOCAL_PATH/node.py --environment $ENVIRONMENT --shard $SHARD --role core --oracle --region $SHARD_REGION --batch)
    if [ -z "$SHARD_IP" ]; then
        echo "No SHARD_IP found from $SHARD, skipping"
        SHARD_CORE_PROVIDER="$($LOCAL_PATH/shard.sh core_provider $ANSIBLE_SSH_USER)"
        if [[ "$SHARD_CORE_PROVIDER" == "nomad" ]]; then
            echo "$SHARD is a nomad shard, not expected to have SHARD_IP"
        else
            RET=2
        fi
    else
        SHARD_READY_IPS="$SHARD_IP,$SHARD_READY_IPS"
    fi
done

SHARD_DRAIN_IPS=""
for SHARD in $SHARDS_DRAIN; do
    SHARD_REGION=$($LOCAL_PATH/shard.py --shard_region --shard $SHARD --environment $ENVIRONMENT)
    SHARD_IP=$($LOCAL_PATH/node.py --environment $ENVIRONMENT --shard $SHARD --role core --oracle --region $SHARD_REGION --batch)
    if [ -z "$SHARD_IP" ]; then
        echo "No SHARD_IP found from $SHARD, skipping"
        SHARD_CORE_PROVIDER="$(SHARD=$SHARD ENVIRONMENT=$ENVIRONMENT $LOCAL_PATH/shard.sh core_provider $ANSIBLE_SSH_USER)"
        if [[ "$SHARD_CORE_PROVIDER" == "nomad" ]]; then
            echo "$SHARD is a nomad shard, not expected to have SHARD_IP"
        else
            RET=2
        fi
    else
        SHARD_DRAIN_IPS="$SHARD_IP,$SHARD_DRAIN_IPS"
    fi
done

cd $ANSIBLE_BUILD_PATH

OUT_RET=0
if [ ! -z "$SHARD_READY_IPS" ]; then
    ansible-playbook ansible/set-signal-state.yml \
        -i "$SHARD_READY_IPS," \
        -e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
        -e "shard_state=ready"
    OUT_RET=$?
fi


SEC_RET=0
if [ ! -z "$SHARD_DRAIN_IPS" ]; then
    ansible-playbook ansible/set-signal-state.yml \
        -i "$SHARD_DRAIN_IPS," \
        -e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
        -e "shard_state=drain"
    SEC_RET=$?
fi

if [[ $OUT_RET -eq 0 ]]; then
    OUT_RET=$SEC_RET
fi

cd -

# check for failures further up in the script, only exit cleanly if all steps were successful
if [ $RET -eq 0 ]; then
    exit $OUT_RET
else
    exit $RET
fi
