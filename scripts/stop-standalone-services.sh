
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

# load oracle defaults
[ -e $LOCAL_PATH/../clouds/oracle.sh ] && . $LOCAL_PATH/../clouds/oracle.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#select new shard numbers if not provided
if [ -z $UNIQUE_ID ]; then
    echo "No UNIQUE_ID set"
    exit 1
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

if [ -z "$ANSIBLE_SSH_USER" ]; then
    if [  -z "$1" ]; then
        ANSIBLE_SSH_USER=$(whoami)
        echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
    else
        ANSIBLE_SSH_USER=$1
        echo "Run ansible as $ANSIBLE_SSH_USER"
    fi
fi

RESOURCE_NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-$UNIQUE_ID"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"
[ -z "$PRIVATE_IP" ] && PRIVATE_IP="$(dig $RESOURCE_NAME_ROOT-internal.$DNS_ZONE_NAME +short)"

if [ -z $PRIVATE_IP ]; then
    echo "No PRIVATE_IP found from $RESOURCE_NAME_ROOT, failing"
    exit 2
fi

cd $ANSIBLE_BUILD_PATH

ansible-playbook ansible/stop-shard-services.yml \
-i "$PRIVATE_IP," \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER"
RET=$?

cd -

exit $RET
