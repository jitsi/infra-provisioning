#!/usr/bin/env bash
set -x

# haproxy-status-lock.sh
# crates a lock file on haproxy to indicate it should not be checked by
# proxymonitor because an operation which uses haproxy-status needs to run
# cleanly (e.g., recycle-haproxy)

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

unset ANSIBLE_SSH_USER
if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
#  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
#  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

if [ "$SKIP_BUILD_CACHE" == "true" ]; then
  export HAPROXY_IGNORE_CACHE="true"
fi

HAPROXY_STATUS_OUTPUT="$LOCAL_PATH/../../haproxy-status/$ENVIRONMENT"

cd $ANSIBLE_BUILD_PATH

# set HAPROXY_CACHE and build cache if needed
SKIP_BUILD_CACHE=$SKIP_BUILD_CACHE . $LOCAL_PATH/haproxy-buildcache.sh 
if [ $? -ne 0 ]; then
    echo "## ERROR: haproxy-buildcache.sh unable to build inventory"
    exit 1
fi

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}
ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}
HAPROXY_STATUS_LOCK_ACTION=${HAPROXY_STATUS_LOCK_ACTION-"unlock"}

echo "## haproxy-status-lock.sh: setting haproxies in ${ANSIBLE_INVENTORY} to ${HAPROXY_STATUS_LOCK_ACTION}"

ansible-playbook --verbose ansible/haproxy-status-lock.yml -i $ANSIBLE_INVENTORY \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-e "hcv_environment=$ENVIRONMENT" \
-e "hcv_haproxy_status_lock_action=$HAPROXY_STATUS_LOCK_ACTION" \
--tags "$DEPLOY_TAGS"

RET=$?

cd -

if [ $RET -ne 0 ]; then
    echo "## ERROR: haproxy-status-lock.yml run failed"
    exit 2
fi

exit $RET
