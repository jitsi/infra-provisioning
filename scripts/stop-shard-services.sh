
#!/bin/bash

set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#load region defaults
[ -e $LOCAL_PATH/../regions/all.sh ] && . $LOCAL_PATH/../regions/all.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#select new shard numbers if not provided
if [ -z $SHARD ]; then
    if [ -z $1 ]; then
        echo "No shard set as SHARD or passed via CLI"
        exit 1
    else
        SHARD=$1
    fi
fi

if [ -z "$ANSIBLE_SSH_USER" ]; then
    if [  -z "$2" ]; then
        ANSIBLE_SSH_USER=$(whoami)
        echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
    else
        ANSIBLE_SSH_USER=$2
        echo "Run ansible as $ANSIBLE_SSH_USER"
    fi
fi

SHARD_IP=$(IP_TYPE="internal" ENVIRONMENT=$ENVIRONMENT SHARD=$SHARD $LOCAL_PATH/shard.sh shard_ip $ANSIBLE_SSH_USER)

if [ -z $SHARD_IP ]; then
    echo "No SHARD_IP found from $SHARD, failing"
    exit 2
fi

cd $ANSIBLE_BUILD_PATH

ansible-playbook ansible/stop-shard-services.yml \
-i "$SHARD_IP," \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER"

cd -

exit $?
