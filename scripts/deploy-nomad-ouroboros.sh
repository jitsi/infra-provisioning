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

[ -z "$OUROBOROS_VERSION" ] && OUROBOROS_VERSION="latest"
[ -z "$OUROBOROS_COUNT" ] && OUROBOROS_COUNT="1"
[ -z "$HEADSCALE_URL" ] && HEADSCALE_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-headscale.${TOP_LEVEL_DNS_ZONE_NAME}"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-ouroboros"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

export NOMAD_VAR_ouroboros_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_ouroboros_version="$OUROBOROS_VERSION"
export NOMAD_VAR_ouroboros_count="$OUROBOROS_COUNT"
export NOMAD_VAR_headscale_url="$HEADSCALE_URL"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="ouroboros-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/ouroboros.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
$LOCAL_PATH/create-oracle-cname-stack.sh

echo ""
echo "Ouroboros UI deployed successfully!"
echo "UI URL: https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
echo "Headscale Server: $HEADSCALE_URL"
echo ""
echo "Required Vault secrets to configure:"
echo ""
echo "1. Headscale API Key:"
echo "   # First, generate an API key in Headscale:"
echo "   nomad exec -job headscale-$ORACLE_REGION headscale apikeys create"
echo "   # Then store it in Vault:"
echo "   vault kv put secret/default/headscale/api api_key='hsk_xxxxxxxxxxxxx'"
echo ""
echo "2. OIDC/Okta Configuration:"
echo "   vault kv put secret/default/ouroboros/oidc \\"
echo "     issuer='https://your-company.okta.com' \\"
echo "     client_id='your-okta-client-id' \\"
echo "     client_secret='your-okta-client-secret'"
echo ""
echo "3. Session Secrets:"
echo "   vault kv put secret/default/ouroboros/session \\"
echo "     secret='\$(openssl rand -base64 32)'"
echo "   vault kv put secret/default/ouroboros/csrf \\"
echo "     secret='\$(openssl rand -base64 32)'"
echo ""
echo "Okta Application Configuration:"
echo "- Redirect URI: https://${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}/auth/oidc/callback"
echo "- Required scopes: openid, profile, email"
