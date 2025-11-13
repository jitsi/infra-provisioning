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

SERVICE_NAME="emqx-haproxy"
export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-${SERVICE_NAME}"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="$SERVICE_NAME-$ORACLE_REGION"

export NOMAD_VAR_domain="${TOP_LEVEL_DNS_ZONE_NAME}"

echo "Deploying EMQX HAProxy load balancer:"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $ORACLE_REGION"
echo "  Nomad DC: $NOMAD_DC"
echo "  HAProxy count: 3 (one per EMQX node)"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/emqx-haproxy.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

if [ $RET -eq 0 ]; then
    echo "EMQX HAProxy job deployed successfully"
    echo ""
    echo "Next steps:"
    echo "  1. Verify HAProxy status: nomad job status $JOB_NAME"
    echo "  2. Check allocations: nomad job allocs $JOB_NAME"
    echo "  3. View HAProxy stats: curl http://<emqx-node-ip>:8080/haproxy_stats"
    echo "  4. Deploy OCI Load Balancer to front HAProxy instances"
fi

exit $RET
