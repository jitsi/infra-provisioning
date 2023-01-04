#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

JVB_POOL_STATUS=$1

if [  -z "$2" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$2
fi

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 1
fi

if [ -z "$JVB_POOL_NAME" ]; then
    echo "No JVB_POOL_NAME set, exiting"
    exit 1
fi

if [ -z "$JVB_POOL_STATUS" ]; then
    echo "No JVB_POOL_STATUS set, exiting"
    exit 1
fi

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
OCI_DATACENTER="$ENVIRONMENT-$ORACLE_REGION"

PORT_OCI=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

ssh -fNT -L127.0.0.1:$PORT_OCI:$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.$DEFAULT_DNS_ZONE_NAME

OCI_CONSUL_URL="https://consul-local.$TOP_LEVEL_DNS_ZONE_NAME:$PORT_OCI"
KV_URL="$OCI_CONSUL_URL/v1/kv/pool-states/$ENVIRONMENT/$JVB_POOL_NAME?dc=$OCI_DATACENTER"

RESPONSE=$(curl -d"$JVB_POOL_STATUS" -X PUT $KV_URL)
if [ $? -eq 0 ]; then
    FINAL_RET=0
else
    FINAL_RET=2
fi
SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
kill $SSH_OCI_PID

exit $FINAL_RET