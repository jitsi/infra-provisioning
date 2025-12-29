#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

# Set Loki and Cloudflare hostnames
export NOMAD_VAR_loki_hostname="${ENVIRONMENT}-${ORACLE_REGION}-loki.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_cloudflare_hostname="${ENVIRONMENT}-${ORACLE_REGION}-loki.cloudflare.${TOP_LEVEL_DNS_ZONE_NAME}"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="cloudflared-$ORACLE_REGION"

echo "Deploying cloudflared tunnel for $ENVIRONMENT in $ORACLE_REGION"
echo "Loki: $NOMAD_VAR_loki_hostname"
echo "Public: $NOMAD_VAR_cloudflare_hostname"
echo "NOMAD_ADDR: $NOMAD_ADDR"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/cloudflared.hcl" | \
  nomad job run \
    -var="dc=$NOMAD_DC" \
    -var="loki_hostname=$NOMAD_VAR_loki_hostname" \
    -var="cloudflare_hostname=$NOMAD_VAR_cloudflare_hostname" \
    -

RET=$?

if [ $RET -eq 0 ]; then
    echo ""
    echo "Cloudflared deployed successfully!"
    echo "Check status: nomad job status $JOB_NAME"
    echo "View logs: nomad alloc logs -f \$(nomad job status $JOB_NAME | grep running | head -1 | awk '{print \$1}')"
    echo ""
    echo "Tunnel will be accessible at: https://${NOMAD_VAR_cloudflare_hostname}"
else
    echo ""
    echo "Cloudflared deployment failed with code $RET"
fi

exit $RET
