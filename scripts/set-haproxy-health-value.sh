#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#Check that haproxy knows about this shards
#[ -z "$SKIP_HAPROXY_CHECK" ] && ../all/bin/check_haproxy_updated.sh

echo "## starting set-haproxy-health-value.sh"

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

#update inventory cache every 2 hours
CACHE_TTL=1440

# set HAPROXY_CACHE and build cache if appropraite
if [ "$SKIP_BUILD_CACHE" == "true" ]; then
    echo "## set-haproxy-health-value.sh using existing inventory cache"
    CACHE_TTL=$CACHE_TTL SKIP_BUILD_CACHE="true" . $LOCAL_PATH/haproxy-buildcache.sh
else
    CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh
fi

if [ $? -ne 0 ]; then
    echo "## ERROR: set-haproxy-health-value.sh unable to build inventory"
    exit 1
fi

ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}

if [ ! -z "$HAPROXY_HEALTH_VALUE" ]; then
    EXTRA="{haproxy_health_up_map_value: $HAPROXY_HEALTH_VALUE}"
fi

ansible-playbook ansible/haproxy-health-value.yml \
-i $ANSIBLE_INVENTORY \
--extra-vars="$EXTRA" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" --vault-password-file .vault-password.txt

exit $?
