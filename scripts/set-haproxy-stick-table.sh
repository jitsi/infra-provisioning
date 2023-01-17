#!/bin/bash
#set -e
set -x
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

[ -z "$STICK_TABLE_RUN" ] && STICK_TABLE_RUN="standalone"
[ -z "$STICK_TABLE_FILENAME" ] && STICK_TABLE_FILENAME="stick-table-${STICK_TABLE_RUN}.json"

cd $ANSIBLE_BUILD_PATH

if [ -z "$STICK_TABLE_ENTRIES_FILE" ]; then
    echo "Need to define STICK_TABLE_ENTRIES_FILE"
    exit 1
fi

if [ ! -f "$STICK_TABLE_ENTRIES_FILE" ]; then
    echo "File $STICK_TABLE_ENTRIES_FILE not found"
    exit 2
fi


cat "${STICK_TABLE_ENTRIES_FILE}" | jq "." > /dev/null
if (( $? != 0 )); then
    echo "Invalid JSON in $STICK_TABLE_ENTRIES_FILE"
    exit 3
fi

#now use ansible to set the stick table state on the proxies
EXTRA="{\"stick_table_entries_file\":\"${STICK_TABLE_ENTRIES_FILE}\", \"stick_table_filename\":\"$STICK_TABLE_FILENAME\"}"

#store inventory cache in local file within current directory
HAPROXY_CACHE="./haproxy.inventory"

#update inventory cache every 2 hours
CACHE_TTL=1440

# set HAPROXY_CACHE and build cache if needed
CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh

ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}

ansible-playbook ansible/haproxy-set-stick-table.yml \
-i $ANSIBLE_INVENTORY \
--extra-vars="$EXTRA" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER"

cd -
