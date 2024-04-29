#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

# alternate value is "registry"
[ -z "$REGISTRY_MODE" ] && REGISTRY_MODE="dhmirror"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-$REGISTRY_MODE"

[ -z "$REGISTRY_HOSTNAME" ] && REGISTRY_HOSTNAME="$RESOURCE_NAME_ROOT.$TOP_LEVEL_DNS_ZONE_NAME"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="${REGISTRY_MODE}-$ORACLE_REGION"

export NOMAD_VAR_oracle_region="$ORACLE_REGION"
export NOMAD_VAR_registry_hostname="$REGISTRY_HOSTNAME"
export NOMAD_VAR_registry_mode="$REGISTRY_MODE"
# use a different redis db for dhmirror
if [[ "$REGISTRY_MODE" == "dhmirror" ]]; then
    export NOMAD_VAR_registry_redis_db="4"
fi
export NOMAD_VAR_oracle_s3_namespace="$ORACLE_S3_NAMESPACE"


sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/registry.hcl" | nomad job run -var="dc=$NOMAD_DC" -


export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
