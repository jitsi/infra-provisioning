#!/bin/bash
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
echo "## rotate-consul-post-attach re-running terraform"
$LOCAL_PATH/../terraform/consul-server/create-consul-server-oracle.sh $SSH_USER
