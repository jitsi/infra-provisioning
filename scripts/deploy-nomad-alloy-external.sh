#!/bin/bash
# Deploy external Alloy for Cloudflare Worker OTLP ingestion

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

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="alloy-external-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"
if [[ "$ENVIRONMENT_TYPE" = "prod" ]]; then
    export NOMAD_VAR_environment_type="prod"
else
    export NOMAD_VAR_environment_type="nonprod"
fi

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/alloy-external.hcl" | \
    nomad job run -var="dc=$NOMAD_DC" -var="environment=$ENVIRONMENT" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad alloy-external job, exiting"
    exit 5
fi

# CNAME: datacenter-specific hostname -> external LB (not internal)
# Note: Environment-only hostname (${ENVIRONMENT}-otlp) routing handled by Cloudflare geo-routing
export RESOURCE_NAME_ROOT="${NOMAD_DC}-otlp"
export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${NOMAD_DC}-nomad-pool-general.${DEFAULT_DNS_ZONE_NAME}"
$LOCAL_PATH/create-oracle-cname-stack.sh
