#!/bin/bash
set -x
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#Check that haproxy knows about this shards
#[ -z "$SKIP_HAPROXY_CHECK" ] && $LOCAL_PATH/check_haproxy_updated.sh

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
[ -z "$SET_SIGNAL_STATE" ] && SET_SIGNAL_STATE="true"
#set the state in AWS
if [ "$SET_SIGNAL_STATE" == "true" ]; then
  export SHARDS_READY
  export SHARDS_DRAIN
  $LOCAL_PATH/set-signal-shard-states.sh $ANSIBLE_SSH_USER
  if [ $? -gt 0 ]; then
    echo "Signal drain failed, shard states likely to be inconsistent"
    RET=2
  fi

  if [ "$SKIP_NON_SIGNAL_STATE" == "true" ]; then
    echo "Skipping non-signal state changes, exiting..."
    exit $RET
  fi
fi

if [ -z "$SKIP_AWS_TAGS" ]; then
  for s in $SHARDS_READY; do
    $LOCAL_PATH/set_shard_state.py $ENVIRONMENT $s ready
  done

  for s in $SHARDS_DRAIN; do
    $LOCAL_PATH/set_shard_state.py $ENVIRONMENT $s drain
  done
fi

#now use ansible to set the shard state on the proxy
set -e

EXTRA=''
#build up the state json, with ready first, then drained
for SHARD in $SHARDS_READY; do
    [ -z "$EXTRA" ] || EXTRA="$EXTRA,"
    EXTRA="$EXTRA{\"shard_name\":\"$SHARD\",\"shard_state\":\"ready\"}"
done
for SHARD in $SHARDS_DRAIN; do
    [ -z "$EXTRA" ] || EXTRA="$EXTRA,"
    EXTRA="$EXTRA{\"shard_name\":\"$SHARD\",\"shard_state\":\"drain\"}"
done
EXTRA="{\"shard_states\":[$EXTRA]}"


#store inventory cache in local file within current directory
HAPROXY_CACHE="./haproxy.inventory"

#update inventory cache every 2 hours
CACHE_TTL=1440

cd $ANSIBLE_BUILD_PATH

# set HAPROXY_CACHE and build cache if needed
CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh

ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}


ansible-playbook ansible/haproxy-shard-states.yml \
-i $ANSIBLE_INVENTORY \
--extra-vars="$EXTRA" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" --vault-password-file .vault-password.txt

OUT_RET=$?

cd -
# check for failures further up in the script, only exit cleanly if all steps were successful
if [ $RET -eq 0 ]; then
  exit $OUT_RET
else
  exit $RET
fi