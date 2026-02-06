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

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$TEMPO_HOSTNAME" ] && TEMPO_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-tempo.$TOP_LEVEL_DNS_ZONE_NAME"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_tempo_hostname="${TEMPO_HOSTNAME}"
export NOMAD_VAR_oracle_s3_namespace="$ORACLE_S3_NAMESPACE"
JOB_NAME="tempo-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/tempo.hcl" | nomad job run -var="dc=$NOMAD_DC" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad tempo job, exiting"
    exit 5
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-tempo"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
