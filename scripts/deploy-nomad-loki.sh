#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    NOMAD_IPS="$(DATACENTER="$ENVIRONMENT-$LOCAL_REGION" OCI_DATACENTERS="$ENVIRONMENT-$LOCAL_REGION" ENVIRONMENT="$ENVIRONMENT" FILTER_ENVIRONMENT="false" SHARD='' RELEASE_NUMBER='' SERVICE="nomad-servers" DISPLAY="addresses" $LOCAL_PATH/consul-search.sh ubuntu)"
    if [ -n "$NOMAD_IPS" ]; then
        NOMAD_IP="$(echo $NOMAD_IPS | cut -d ' ' -f1)"
        export NOMAD_ADDR="http://$NOMAD_IP:4646"
    else
        echo "No NOMAD_IPS for in environment $ENVIRONMENT in consul"
        exit 5
    fi
fi

if [ -z "$NOMAD_ADDR" ]; then
    echo "Failed to set NOMAD_ADDR, exiting"
    exit 5
fi

[ -z "$LOKI_HOSTNAME" ] && LOKI_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-loki.$TOP_LEVEL_DNS_ZONE_NAME"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_loki_hostname="${LOKI_HOSTNAME}"
JOB_NAME="loki-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/loki.hcl" | nomad job run -var="dc=$NOMAD_DC" -


export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-loki"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
