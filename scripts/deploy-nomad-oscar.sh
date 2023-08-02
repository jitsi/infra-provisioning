#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

if [ -z "$DOMAIN" ]; then
    echo "No DOMAIN set, exiting"
    exit 2
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

[ -z "$OSCAR_TEMPLATE_TYPE" ] && OSCAR_TEMPLATE_TYPE="core"

NOMAD_CONFIG_FILE="$LOCAL_PATH/../nomad/oscar-${OSCAR_TEMPLATE_TYPE}.hcl"

if [ ! -f "$NOMAD_CONFIG_FILE" ]; then
    echo "Oscar config file $NOMAD_CONFIG_FILE does not exist."
    exit 2
fi

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

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

JOB_NAME="oscar-$ORACLE_REGION"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-oscar"

export NOMAD_VAR_dc="$NOMAD_DC"
export NOMAD_VAR_oscar_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_cloudprober_version="latest"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_region="$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_CONFIG_FILE" | nomad job run -verbose -var="dc=$NOMAD_DC" -var="domain=$DOMAIN" -var="cloudprober_version=latest" -
