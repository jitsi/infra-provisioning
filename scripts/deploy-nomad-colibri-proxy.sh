#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

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

[ -z "$REGIONS" ] && REGIONS="$DRG_PEER_REGIONS"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"

NOMAD_DC="[]"
for ORACLE_REGION in $REGIONS; do
    NOMAD_DC="$( echo "$NOMAD_DC" "[\"$ENVIRONMENT-$ORACLE_REGION\"]" | jq -c -s '.|add')"
done

[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

COLIBRI_PROXY_SECOND_OCTET_REGEXP_VARIABLE="jvb_colibri_proxy_second_octet_regexp"
COLIBRI_PROXY_THIRD_OCTET_REGEXP_VARIABLE="jvb_colibri_proxy_third_octet_regexp"
COLIBRI_PROXY_FOURTH_OCTET_REGEXP_VARIABLE="jvb_colibri_proxy_fourth_octet_regexp"

COLIBRI_PROXY_SECOND_OCTET_REGEXP="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${COLIBRI_PROXY_SECOND_OCTET_REGEXP_VARIABLE} -)"
COLIBRI_PROXY_THIRD_OCTET_REGEXP="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${COLIBRI_PROXY_THIRD_OCTET_REGEXP_VARIABLE} -)"
COLIBRI_PROXY_FOURTH_OCTET_REGEXP="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${COLIBRI_PROXY_FOURTH_OCTET_REGEXP_VARIABLE} -)"

if [ "$COLIBRI_PROXY_SECOND_OCTET_REGEXP" != "null" ]; then
    export NOMAD_VAR_colibri_proxy_second_octet_regexp="$COLIBRI_PROXY_SECOND_OCTET_REGEXP"
fi
if [ "$COLIBRI_PROXY_THIRD_OCTET_REGEXP" != "null" ]; then
    export NOMAD_VAR_colibri_proxy_third_octet_regexp="$COLIBRI_PROXY_THIRD_OCTET_REGEXP"
fi
if [ "$COLIBRI_PROXY_FOURTH_OCTET_REGEXP" != "null" ]; then
    export NOMAD_VAR_colibri_proxy_fourth_octet_regexp="$COLIBRI_PROXY_FOURTH_OCTET_REGEXP"
fi
export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_octo_region="$ORACLE_REGION"

JOB_NAME="colibri-proxy"
export NOMAD_VAR_dc="$NOMAD_DC"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/colibri-proxy.hcl" | nomad job run -
