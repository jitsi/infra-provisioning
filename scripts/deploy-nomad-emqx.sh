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

# EMQX specific configuration
[ -z "$EMQX_VERSION" ] && EMQX_VERSION="5.8.3"
[ -z "$EMQX_COUNT" ] && EMQX_COUNT="3"
[ -z "$EMQX_CLUSTER_COOKIE" ] && EMQX_CLUSTER_COOKIE="emqx_secret_cookie_$(openssl rand -hex 16)"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

SERVICE_NAME="emqx"
export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-${SERVICE_NAME}"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="$SERVICE_NAME-$ORACLE_REGION"

export NOMAD_VAR_emqx_version=$EMQX_VERSION
export NOMAD_VAR_emqx_count=$EMQX_COUNT
export NOMAD_VAR_emqx_cluster_cookie=$EMQX_CLUSTER_COOKIE
export NOMAD_VAR_domain="${TOP_LEVEL_DNS_ZONE_NAME}"

echo "Deploying EMQX cluster:"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $ORACLE_REGION"
echo "  Nomad DC: $NOMAD_DC"
echo "  Version: $EMQX_VERSION"
echo "  Node Count: $EMQX_COUNT"
echo "  Dashboard URL: https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/emqx.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

if [ $RET -eq 0 ]; then
    echo "EMQX job deployed successfully"
    echo ""
    echo "Next steps:"
    echo "  1. Verify cluster status: nomad job status $JOB_NAME"
    echo "  2. Check allocations: nomad job allocs $JOB_NAME"
    echo "  3. View logs: nomad alloc logs -job $JOB_NAME -task emqx"
    echo "  4. Access dashboard: https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
    echo "  5. Default credentials: admin / public (CHANGE IMMEDIATELY)"
fi

# Create CNAME for dashboard
export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $RET
