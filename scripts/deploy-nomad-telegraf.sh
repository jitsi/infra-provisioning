#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$ORACLE_REGION"

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

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../config/vars.yml"

WAVEFRONT_PROXY_URL="https://ops-prod-us-phoenix-1-wfproxy.jitsi.net"

if [ -z "$WAVEFRONT_PROXY_URL" ]; then
    WAVEFRONT_PROXY_VARIABLE="wavefront_proxy_host_by_cloud.$ENVIRONMENT-$ORACLE_REGION"
    WAVEFRONT_PROXY_URL="http://$(cat $CONFIG_VARS_FILE | yq eval .${WAVEFRONT_PROXY_VARIABLE} -):2878"
fi

export NOMAD_VAR_wavefront_proxy_url="$WAVEFRONT_PROXY_URL"
export NOMAD_VAR_environment="$ENVIRONMENT"

JOB_NAME="telegraf-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/telegraf.hcl" | nomad job run -var="dc=$NOMAD_DC" -
