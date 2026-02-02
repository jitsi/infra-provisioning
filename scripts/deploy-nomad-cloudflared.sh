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

# Load Cloudflare API token if not already set
ENCRYPTED_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/cloudflare.yml"
CLOUDFLARE_API_TOKEN_VARIABLE="cf_api_tokens.$ENVIRONMENT"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    set -e
    set -o pipefail
    export CLOUDFLARE_API_TOKEN="$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $LOCAL_PATH/../.vault-password.txt | yq eval ".${CLOUDFLARE_API_TOKEN_VARIABLE}" -)"
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "No token CLOUDFLARE_API_TOKEN found or decrypted from $ENCRYPTED_CREDENTIALS_FILE $CLOUDFLARE_API_TOKEN_VARIABLE"
    exit 2
fi

if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
    if [ -z "$DOMAIN" ]; then
        echo "No DOMAIN set, cannot look up CLOUDFLARE_ACCOUNT_ID"
        exit 2
    fi

    # Get the account name for this domain
    ACCOUNT_NAME="$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $LOCAL_PATH/../.vault-password.txt | yq eval ".cf_domain_accounts[\"$DOMAIN\"]" -)"

    if [ -z "$ACCOUNT_NAME" ] || [ "$ACCOUNT_NAME" = "null" ]; then
        echo "Error: No account mapping found for domain $DOMAIN"
        exit 2
    fi
    echo "Account name: $ACCOUNT_NAME"

    # Get the account ID for this account
    CLOUDFLARE_ACCOUNT_ID="$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $LOCAL_PATH/../.vault-password.txt | yq eval ".cf_account_ids[\"$ACCOUNT_NAME\"]" -)"

    if [ -z "$CLOUDFLARE_ACCOUNT_ID" ] || [ "$CLOUDFLARE_ACCOUNT_ID" = "null" ]; then
        echo "Error: No account ID found for account $ACCOUNT_NAME"
        exit 2
    fi
fi
echo "Account ID: $CLOUDFLARE_ACCOUNT_ID"

# Look up Cloudflare tunnel ID by name
TUNNEL_NAME="${ENVIRONMENT}-${ORACLE_REGION}"
echo "Looking up Cloudflare tunnel: $TUNNEL_NAME"

TUNNEL_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME")

TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | jq -r '.result[0].id // empty')

if [ -z "$TUNNEL_ID" ]; then
    echo "Failed to find Cloudflare tunnel with name: $TUNNEL_NAME"
    echo "API response: $TUNNEL_RESPONSE"
    exit 2
fi

echo "Found tunnel ID: $TUNNEL_ID"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

# Set Loki and Cloudflare hostnames
export NOMAD_VAR_service_zone="${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_cloudflare_zone="${DOMAIN}"
export NOMAD_VAR_tunnel_id="${TUNNEL_ID}"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="cloudflared-$ORACLE_REGION"

echo "Deploying cloudflared tunnel $NOMAD_VAR_tunnel_id for $ENVIRONMENT in $ORACLE_REGION with service zone $NOMAD_VAR_service_zone and CF zone $NOMAD_VAR_cloudflare_zone"
echo "NOMAD_ADDR: $NOMAD_ADDR"

# sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/cloudflared.hcl" | \
#   nomad job run \
#     -var="dc=$NOMAD_DC" \
#     -

# RET=$?
RET=5

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
