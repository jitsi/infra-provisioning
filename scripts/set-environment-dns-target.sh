#!/bin/bash

# Script to toggle the main CNAME record for an environment between
# Cloudflare CDN and geo-DNS (Oracle)
#
# Usage:
#   ./set-environment-dns-target.sh <ENVIRONMENT> <TARGET> [--dry-run]
#   ENVIRONMENT=meet-jit-si TARGET=cdn ./set-environment-dns-target.sh
#
# TARGET must be either:
#   cdn - Points to <domain>.cdn.cloudflare.net
#   geo - Points to <environment>.oracle-geo.infra.jitsi.net

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# source cloud defaults for GEO_DNS_ZONE_NAME
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

# Default geo-DNS zone name if not set from oracle.sh
[ -z "$GEO_DNS_ZONE_NAME" ] && GEO_DNS_ZONE_NAME="oracle-geo.infra.jitsi.net"

# Default TTL for CNAME records
[ -z "$CNAME_TTL" ] && CNAME_TTL=300

# Parse parameters
[ -z "$ENVIRONMENT" ] && ENVIRONMENT="$1"
[ -z "$TARGET" ] && TARGET="$2"
[ -z "$DRY_RUN" ] && DRY_RUN="false"

# Check for --dry-run flag in arguments
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN="true"
    fi
done

# Function to print usage
usage() {
    echo "Usage: $0 <ENVIRONMENT> <TARGET> [--dry-run]"
    echo "       ENVIRONMENT=<env> TARGET=<target> $0 [--dry-run]"
    echo ""
    echo "Environments: meet-jit-si, beta-meet-jit-si, prod-8x8, stage-8x8, jitsi-net"
    echo "Targets: cdn, geo"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would change without making changes"
}

# Function to get environment configuration
get_env_config() {
    local env="$1"
    case "$env" in
        "meet-jit-si")
            DOMAIN="meet.jit.si"
            DNS_ZONE_ID="ZBEPMHA286RBX"
            ;;
        "beta-meet-jit-si")
            DOMAIN="beta.meet.jit.si"
            DNS_ZONE_ID="ZBEPMHA286RBX"
            ;;
        "prod-8x8")
            DOMAIN="8x8.vc"
            DNS_ZONE_ID="Z2IOJOJTQE93UB"
            ;;
        "stage-8x8")
            DOMAIN="stage.8x8.vc"
            DNS_ZONE_ID="Z2IOJOJTQE93UB"
            ;;
        "jitsi-net")
            DOMAIN="chaos.jitsi.net"
            DNS_ZONE_ID="ZJ6O8D5EJO64L"
            ;;
        *)
            echo "ERROR: Unknown environment: $env"
            echo "Supported environments: meet-jit-si, beta-meet-jit-si, prod-8x8, stage-8x8, jitsi-net"
            exit 4
            ;;
    esac
}

# Validate ENVIRONMENT
if [ -z "$ENVIRONMENT" ]; then
    echo "ERROR: No ENVIRONMENT provided."
    echo ""
    usage
    exit 1
fi

# Validate TARGET
if [ -z "$TARGET" ]; then
    echo "ERROR: No TARGET provided."
    echo ""
    usage
    exit 2
fi

# Validate TARGET value
if [[ "$TARGET" != "cdn" && "$TARGET" != "geo" ]]; then
    echo "ERROR: Invalid TARGET: $TARGET"
    echo "TARGET must be either 'cdn' or 'geo'"
    exit 3
fi

# Get environment configuration
get_env_config "$ENVIRONMENT"

# Calculate new CNAME target based on TARGET
if [[ "$TARGET" == "cdn" ]]; then
    NEW_CNAME_TARGET="${DOMAIN}.cdn.cloudflare.net"
else
    NEW_CNAME_TARGET="${ENVIRONMENT}.${GEO_DNS_ZONE_NAME}"
fi

# Route53 requires trailing dot for record names
RECORD_NAME="${DOMAIN}."

echo "Looking up current CNAME record for ${DOMAIN}..."

# Query current CNAME record
CURRENT_RECORD=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$DNS_ZONE_ID" \
    --query "ResourceRecordSets[?Name == '${RECORD_NAME}']|[?Type == 'CNAME']|[0]" \
    2>&1)

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to query Route53 for zone $DNS_ZONE_ID"
    echo "$CURRENT_RECORD"
    exit 10
fi

# Parse current target
if [[ "$CURRENT_RECORD" == "null" ]]; then
    echo "No existing CNAME record found for ${DOMAIN}"
    CURRENT_TARGET="<none>"
else
    CURRENT_TARGET=$(echo "$CURRENT_RECORD" | jq -r '.ResourceRecords[0].Value')
    CURRENT_TTL=$(echo "$CURRENT_RECORD" | jq -r '.TTL')
    echo "Current CNAME target: $CURRENT_TARGET (TTL: $CURRENT_TTL)"
fi

# Check if change is needed (handle with or without trailing dot)
if [[ "$CURRENT_TARGET" == "${NEW_CNAME_TARGET}." ]] || [[ "$CURRENT_TARGET" == "$NEW_CNAME_TARGET" ]]; then
    echo ""
    echo "CNAME already points to $NEW_CNAME_TARGET - no change needed"
    exit 0
fi

# Display change summary
echo ""
echo "=== DNS Change Summary ==="
echo "Environment: $ENVIRONMENT"
echo "Domain:      $DOMAIN"
echo "Zone ID:     $DNS_ZONE_ID"
echo "Current:     $CURRENT_TARGET"
echo "New target:  $NEW_CNAME_TARGET"
echo "TTL:         $CNAME_TTL"
echo "=========================="

# Build the change batch JSON
CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${RECORD_NAME}",
                "Type": "CNAME",
                "TTL": ${CNAME_TTL},
                "ResourceRecords": [
                    {
                        "Value": "${NEW_CNAME_TARGET}"
                    }
                ]
            }
        }
    ]
}
EOF
)

# Handle dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN MODE ==="
    echo "Would execute the following change batch:"
    echo "$CHANGE_BATCH" | jq .
    echo ""
    echo "Command that would be executed:"
    echo "aws route53 change-resource-record-sets --hosted-zone-id $DNS_ZONE_ID --change-batch '<change_batch>'"
    echo ""
    echo "No changes were made."
    exit 0
fi

# Execute the change
echo ""
echo "Applying DNS change..."

CHANGE_RESULT=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$DNS_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" 2>&1)

if [ $? -eq 0 ]; then
    CHANGE_ID=$(echo "$CHANGE_RESULT" | jq -r '.ChangeInfo.Id')
    CHANGE_STATUS=$(echo "$CHANGE_RESULT" | jq -r '.ChangeInfo.Status')
    echo "Change submitted successfully!"
    echo "Change ID: $CHANGE_ID"
    echo "Status: $CHANGE_STATUS"
    exit 0
else
    echo "ERROR: Failed to apply DNS change"
    echo "$CHANGE_RESULT"
    exit 20
fi
