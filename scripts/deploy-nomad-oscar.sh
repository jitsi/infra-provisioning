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

[ -z "$OSCAR_TEMPLATE_TYPE" ] && OSCAR_TEMPLATE_TYPE="core"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

JOB_NAME="oscar-$ORACLE_REGION"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-oscar"

export NOMAD_VAR_dc="$NOMAD_DC"
export NOMAD_VAR_oscar_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_cloudprober_version="latest"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_top_level_domain="$TOP_LEVEL_DNS_ZONE_NAME"
export NOMAD_VAR_region="$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/templates/oscar-head.hcl" | cat - $NOMAD_JOB_PATH/templates/oscar-${OSCAR_TEMPLATE_TYPE}-foot.hcl | nomad job run -verbose -var="dc=$NOMAD_DC" -var="domain=$DOMAIN" -var="cloudprober_version=latest" -

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh