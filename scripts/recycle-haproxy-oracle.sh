#!/bin/bash

# recycle-haproxy-oracle.sh
# replace haproxies in an Oracle environment with fresh instances via scaling up
# the instance pool, reconfiguring to allow a remesh, then scaling back down

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

# get ORACLE_REGIONS
. $LOCAL_PATH/../clouds/all.sh

# set up ansible configuration files
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

echo "## recycle-haproxy-oracle: beginning"

HAPROXY_CONSUL_TEMPLATE="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".haproxy_enable_consul_template" -)"
if [[ "$HAPROXY_CONSUL_TEMPLATE" == "null" ]]; then
    HAPROXY_CONSUL_TEMPLATE="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".haproxy_enable_consul_template" -)"
fi

if [ -z "$HAPROXY_CONSUL_TEMPLATE" ]; then
    HAPROXY_CONSUL_TEMPLATE="false"
fi

echo -e "## recycle-haproxy-oracle: HAPROXY_CONSUL_TEMPLATE: ${HAPROXY_CONSUL_TEMPLATE}"

if [  -z "$1" ]; then
  ANSIBLE_SSH_USER=$(whoami)
  echo "## recycle-haproxy-oracle: ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "## recycle-haproxy-oracle: run ansible as $ANSIBLE_SSH_USER"
fi

[ -z "$SHARD_ROLE" ] && SHARD_ROLE="haproxy"

function scale_up_haproxy_oracle() {
  echo -e "\n## capture snapshot of complete haproxy inventory and stick table status, repair split brains"
  HAPROXY_CACHE_TTL="0" HAPROXY_STATUS_IGNORE_LOCK="true" HAPROXY_SNAPSHOT="true" $LOCAL_PATH/haproxy-status.sh $ANSIBLE_SSH_USER
  if [ $? -gt 0 ]; then
    echo "## ERROR: haproxy-status.sh failed to pull inventory, exiting..."
    return 1
  fi

  echo -e "\n## recycle-haproxy-oracle: double the size of all haproxy instance pools"
  ENVIRONMENT=$ENVIRONMENT ROLE=haproxy $LOCAL_PATH/pool.py double --wait

  echo -e "\n## wait 90 seconds for ssh keys to get installed on new instances"
  sleep 90

  if [[ $HAPROXY_CONSUL_TEMPLATE != "true" ]]; then
    echo -e "\n## reconfigure haproxies, wait for mesh, wait for lb to report healthy, set to healthy"
    HAPROXY_CACHE_TTL=0 HAPROXY_STATUS_KEEP_LOCKED="true" $LOCAL_PATH/reload-haproxy.sh $ANSIBLE_SSH_USER
    if [ $? -gt 0 ]; then
      echo "## ERROR: reload-haproxy.sh failed, exiting..."
      return 1
    fi
  fi

  echo "## wait for all haproxy load balancers to report healthy"
  ENVIRONMENT=$ENVIRONMENT ROLE=haproxy $LOCAL_PATH/pool.py lb_health --timeout 15
  POOL_RET=$?
  if [ $POOL_RET -gt 0 ]; then
    echo "## reload-haproxy: at least one haproxy load balancer failed to go healthy, EXITING WITHOUT SETTING HEALTHY"
    exit 1
  fi

  echo -e "\n## post scale-up split brain repair"
  HAPROXY_CACHE_TTL="0" HAPROXY_STATUS_IGNORE_LOCK="true" $LOCAL_PATH/haproxy-status.sh $ANSIBLE_SSH_USER
  if [ $? -gt 0 ]; then
    echo "## ERROR: haproxy-status.sh failed to pull inventory, exiting..."
    return 1
  fi
}

function scale_down_haproxy_oracle() {
  echo -e "\n## recycle-haproxy-oracle: get list of IPs of instances to detach"
  DETACHABLE_IPS=$(ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=haproxy $LOCAL_PATH/pool.py halve --onlyip)

  echo -e "\n## recycle-haproxy-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and setting them unhealthy"
  for IP in $DETACHABLE_IPS; do
    timeout 20 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $ANSIBLE_SSH_USER@$IP 'echo "up false" | sudo tee /etc/haproxy/maps/up.map;echo "clear map /etc/haproxy/maps/up.map" | sudo socat /var/run/haproxy/admin.sock stdio'
  done

  echo -e "\n## recycle-haproxy-oracle: wait for load balancers health checks to see old haproxies as unhealthy"
  sleep 60

  echo -e "\n## recycle-haproxy-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and shutting down consul cleanly"
  for IP in $DETACHABLE_IPS; do
    timeout 20 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $ANSIBLE_SSH_USER@$IP "sudo service consul stop"
  done

  echo -e "\n## recycle-haproxy-oracle: halve the size of all haproxy instance pools"
  ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=haproxy $LOCAL_PATH/pool.py halve --wait

  # do not do this with consul-template
  if [[ "$HAPROXY_CONSUL_TEMPLATE" != "true" ]]; then
    echo -e "\n## reconfigure remaining haproxies so they drop out the originals from the peer mesh"
    HAPROXY_CACHE_TTL=0 HAPROXY_STATUS_KEEP_LOCKED="true" $LOCAL_PATH/reload-haproxy.sh $ANSIBLE_SSH_USER
    if [ $? -gt 0 ]; then
      echo "## ERROR: reload-haproxy.sh failed, exiting..."
      return 1
    fi
  fi
}

function sanity_check() {
  echo -e "\n## recycle-haproxy-oracle: sanity check - capture new inventory and compare stick table status with snapshot"
  HAPROXY_CACHE_TTL="0" HAPROXY_STATUS_IGNORE_LOCK="true" HAPROXY_SNAPSHOT="true" HAPROXY_STATUS_COMPARE_SNAPSHOT="true" $LOCAL_PATH/haproxy-status.sh $ANSIBLE_SSH_USER
  if [ $? -gt 0 ]; then
    echo "## WARNING: haproxy-status.sh check failed to exit cleanly"
  fi
}

echo -e "\n## recycle-haproxy-oracle: recycling pools in ${ENVIRONMENT}. current inventory:"
ENVIRONMENT=$ENVIRONMENT ROLE=haproxy $LOCAL_PATH/pool.py inventory

RET_SCALE_UP=0
RET_SCALE_DOWN=0

if [ "$SCALE_DOWN_ONLY" == "true" ]; then
  echo "## recycle-haproxy-oracle: skipping scale up"
else
  echo "## recycle-haproxy-oracle: scaling up"
  scale_up_haproxy_oracle
  RET_SCALE_UP=$?
  if [ $RET_SCALE_UP -gt 0 ]; then
    echo -e "\n## ERROR: RECYCLE FAILED TO SCALE UP"
  fi
fi

if [ "$SCALE_UP_ONLY" == "true" ] || [ $RET_SCALE_UP -gt 0 ]; then
  sanity_check
else
  echo -e "\n## recycle-haproxy-oracle: scaling down"
  scale_down_haproxy_oracle
  RET_SCALE_DOWN=$?
  sanity_check
  if [ $RET_SCALE_DOWN -gt 0 ]; then
    echo -e "## ERROR: RECYCLE FAILED TO SCALE DOWN"
  fi
fi

if [ "$SCALE_UP_ONLY" == "true" ]; then
  echo -e "\n## recycle-haproxy-oracle: skipped scale down - complete with SCALE_DOWN_ONLY=true"
fi

echo "## recycle-haproxy-oracle: finished scaling, pool inventory is now:"
ENVIRONMENT=$ENVIRONMENT ROLE=haproxy $LOCAL_PATH/pool.py inventory

echo "## recycle-haproxy-oracle completed"

if [ $RET_SCALE_UP -gt 0 ] || [ $RET_SCALE_DOWN -gt 0 ]; then
  echo "## recycle-haproxy-oracle encountered one or more ERROR conditions"
  exit 5 
fi
