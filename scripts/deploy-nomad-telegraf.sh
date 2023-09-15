#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../config/vars.yml"

# WAVEFRONT_PROXY_URL="https://ops-prod-us-phoenix-1-wfproxy.jitsi.net"

if [ -z "$WAVEFRONT_PROXY_URL" ]; then
    WAVEFRONT_PROXY_VARIABLE="wavefront_proxy_host_by_cloud.$ENVIRONMENT-$ORACLE_REGION"
    WAVEFRONT_PROXY_URL="$(cat $CONFIG_VARS_FILE | yq eval .${WAVEFRONT_PROXY_VARIABLE} -)"
    echo "$WAVEFRONT_PROXY_URL" | grep -q "https"
    if [[ $? -gt 0 ]]; then
        WAVEFRONT_PROXY_URL="http://$WAVEFRONT_PROXY_URL:2878"
    fi
fi

export NOMAD_VAR_wavefront_proxy_url="$WAVEFRONT_PROXY_URL"
export NOMAD_VAR_environment="$ENVIRONMENT"

JOB_NAME="telegraf-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/telegraf.hcl" | nomad job run -var="dc=$NOMAD_DC" -
