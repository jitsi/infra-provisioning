#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

set -x

echo "## starting haproxy-set-release-ga.sh"

if [ -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

if [ -z "$RELEASE_NUMBER" ]; then
  echo "## ERROR in haproxy-set-release-ga: RELEASE_NUMBER must be set"
  exit 42
fi

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"
cd $ANSIBLE_BUILD_PATH

[ -z "$CACHE_TTL" ] && CACHE_TTL=0

# set HAPROXY_CACHE and build cache if appropraite
if [ "$SKIP_BUILD_CACHE" == "true" ]; then
    echo "## haproxy-set-release-ga.sh using existing inventory cache"
    CACHE_TTL=$CACHE_TTL SKIP_BUILD_CACHE="true" . $LOCAL_PATH/scripts/haproxy-buildcache.sh
else
    CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/scripts/haproxy-buildcache.sh
fi

if [ $? -ne 0 ]; then
    echo "## ERROR: haproxy-set-release-ga.sh unable to build inventory"
    exit 1
fi

ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}

ansible-playbook ansible/haproxy-release-live.yml \
-i $ANSIBLE_INVENTORY \
-e "haproxy_release_live=release-$RELEASE_NUMBER" \
-e "$EXTRA" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" --vault-password-file .vault-password.txt
RET=$?

cd -
exit $RET
