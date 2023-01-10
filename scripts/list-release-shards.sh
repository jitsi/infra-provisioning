#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
else
  SSH_USER=$1
fi

SHARDS=""
for rel in $RELEASE_NUMBER; do
    SHARDS="$(RELEASE_NUMBER=$rel ENVIRONMENT=$ENVIRONMENT $LOCAL_PATH/shard.sh list $SSH_USER) $SHARDS"
done
echo $SHARDS