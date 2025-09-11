#!/bin/bash


LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$NOMAD_REGIONS" ] && NOMAD_REGIONS="us-phoenix-1"

for ORACLE_REGION in $NOMAD_REGIONS; do
    export ORACLE_REGION
    "$LOCAL_PATH/redrive-async-transcriber-queue.sh"
done
