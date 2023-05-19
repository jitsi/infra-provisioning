#!/bin/bash

# reload-haproxy.sh
# rerun configure scripts on haproxies and then reload

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

echo "## reload-haproxy: beginning"

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [  -z "$1" ]; then
  ANSIBLE_SSH_USER=$(whoami)
  echo "## reload-haproxy: ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "## reload-haproxy: run ansible as $ANSIBLE_SSH_USER"
fi

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

[ -z "$LOG_DEST" ] && LOG_DEST="../../test-results"

if [ "$HAPROXY_REMOTE_ROTATE" == "true" ]; then
  ANSIBLE_PLAYBOOK_FILE="haproxy-reload-remote.yml"
fi

[ -z "$ANSIBLE_PLAYBOOK_FILE" ] && ANSIBLE_PLAYBOOK_FILE="haproxy-reload-parallel.yml"

# defaults to update inventory cache every 2 hours
CACHE_TTL=${HAPROXY_CACHE_TTL-"1440"}

SKIP_BUILD_CACHE=${HAPROXY_IGNORE_CACHE-"false"}

cd $ANSIBLE_BUILD_PATH

# set HAPROXY_CACHE and build cache if needed
SKIP_BUILD_CACHE=$SKIP_BUILD_CACHE CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}

HAPROXY_STATUS_KEEP_LOCKED=${HAPROXY_STATUS_KEEP_LOCKED-"false"}

echo -e "\n## configuring and reloading haproxies with ${ANSIBLE_PLAYBOOK_FILE}"
ansible-playbook ansible/$ANSIBLE_PLAYBOOK_FILE \
-i $ANSIBLE_INVENTORY \
--extra-vars "{haproxy_configure_only: true}" \
--extra-vars "hcv_environment=$ENVIRONMENT prosody_domain_name=$DOMAIN haproxy_configure_log_dest=$LOG_DEST $EXTRA_VARS" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" --vault-password-file .vault-password.txt \
--tags "$DEPLOY_TAGS"
ANSIBLE_RET=$?
if [ $ANSIBLE_RET -gt 0 ]; then
    echo "## reload-haproxy ERROR: ${ANSIBLE_PLAYBOOK_FILE} exited nonzero value ${ANSIBLE_RET}"
fi

if [ "$ANSIBLE_RET" -gt 0 ]; then
  FINAL_RET=5
  echo "## reload-haproxy: EXITING WITHOUT SETTING HEALTHY - haproxy reload playbook error"
  exit $FINAL_RET
fi

echo "## wait for all haproxy load balancers to report healthy"
ENVIRONMENT=$ENVIRONMENT ROLE=haproxy $LOCAL_PATH/pool.py lb_health --wait
POOL_RET=$?
if [ "$POOL_RET" -gt 0 ]; then
  echo "## reload-haproxy: EXITING WITHOUT SETTING HEALTHY - at least one haproxy load balancer is still not healthy"
  exit 1
fi

echo "## reload-haproxy: setting all haproxies to healthy"
SKIP_BUILD_CACHE=true HAPROXY_HEALTH_VALUE=true $LOCAL_PATH/set-haproxy-health-value.sh $ANSIBLE_SSH_USER
if [ $? -gt 0 ]; then
  echo "## ERROR: set-haproxy-health-value.sh failed"
  exit 20
fi
