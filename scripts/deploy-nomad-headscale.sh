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

[ -z "$HEADSCALE_VERSION" ] && HEADSCALE_VERSION="latest"
[ -z "$HEADSCALE_COUNT" ] && HEADSCALE_COUNT="1"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-headscale"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

export NOMAD_VAR_headscale_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_headscale_version="$HEADSCALE_VERSION"
export NOMAD_VAR_headscale_count="$HEADSCALE_COUNT"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="headscale-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/headscale.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
$LOCAL_PATH/create-oracle-cname-stack.sh

echo ""
echo "Headscale deployed successfully!"
echo "Server URL: https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
echo ""
echo "Next steps:"
echo "1. Create a user: nomad exec -job $JOB_NAME headscale users create myuser"
echo "2. Generate auth keys: nomad exec -job $JOB_NAME headscale --user myuser preauthkeys create --reusable --expiration 24h"
echo "3. Use the auth key with TAILSCALE_AUTH_KEY and set HEADSCALE_URL=https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
