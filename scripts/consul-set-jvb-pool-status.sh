#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

JVB_POOL_STATUS=$1

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

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
OCI_DATACENTER="$ENVIRONMENT-$ORACLE_REGION"

OCI_CONSUL_URL="https://$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"
KV_URL="$OCI_CONSUL_URL/v1/kv/pool-states/$ENVIRONMENT/$JVB_POOL_NAME?dc=$OCI_DATACENTER"

RESPONSE=$(curl -d"$JVB_POOL_STATUS" -X PUT $KV_URL)
if [ $? -eq 0 ]; then
    FINAL_RET=0
else
    FINAL_RET=2
fi

exit $FINAL_RET