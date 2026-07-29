#!/bin/bash
set -e
set -o pipefail

# Converts a Route53 zone dump to Terraform cloudflare_record resources.
#
# Usage:
#   ./route53-to-cloudflare-tf.sh [--dry-run] [--dump-file <path>] [--existing-tf <path>]
#
# Environment variables:
#   DOMAIN              - Domain to migrate (default: 8x8.vc)
#   ROUTE53_ZONE_ID     - Route53 hosted zone ID (default: Z2IOJOJTQE93UB for 8x8.vc)
#
# Outputs:
#   - <domain>-cloudflare-records.tf    (new Terraform resources)
#   - <domain>-tf-import.sh             (import commands for records that already exist in CF)
#   - <domain>-warnings.txt             (records needing manual review)
#   - <domain>-route53-dump.json        (raw Route53 dump, unless --dump-file provided)

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# Defaults
[ -z "$DOMAIN" ] && DOMAIN="8x8.vc"
[ -z "$ROUTE53_ZONE_ID" ] && ROUTE53_ZONE_ID="Z2IOJOJTQE93UB"
DRY_RUN=false
DUMP_FILE=""
EXISTING_TF=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --dump-file)
            DUMP_FILE="$2"
            shift 2
            ;;
        --existing-tf)
            EXISTING_TF="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--dump-file <path>] [--existing-tf <path>]"
            exit 1
            ;;
    esac
done

# Validate tools
for cmd in aws jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not found"
        exit 2
    fi
done

# Output file names (use domain with dots replaced by dashes)
DOMAIN_SLUG=$(echo "$DOMAIN" | tr '.' '-')
TF_OUTPUT="${DOMAIN_SLUG}-cloudflare-records.tf"
IMPORT_OUTPUT="${DOMAIN_SLUG}-tf-import.sh"
WARNINGS_OUTPUT="${DOMAIN_SLUG}-warnings.txt"

# Counters
CREATED=0
SKIPPED_EXISTING=0
SKIPPED_SOA_NS=0
SKIPPED_NAPTR=0
WARNED_ALIAS=0
WARNED_ROUTING=0
TOTAL=0

# ── Step 1: Get Route53 dump ──────────────────────────────────────────────────

if [ -n "$DUMP_FILE" ]; then
    if [ ! -f "$DUMP_FILE" ]; then
        echo "ERROR: Dump file not found: $DUMP_FILE"
        exit 3
    fi
    echo "Using existing dump file: $DUMP_FILE"
    R53_DUMP="$DUMP_FILE"
else
    R53_DUMP="${DOMAIN_SLUG}-route53-dump.json"
    echo "Dumping Route53 records for $DOMAIN (zone $ROUTE53_ZONE_ID)..."
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$ROUTE53_ZONE_ID" \
        --output json > "$R53_DUMP"
    echo "Saved $(jq '.ResourceRecordSets | length' "$R53_DUMP") records to $R53_DUMP"
fi

TOTAL=$(jq '.ResourceRecordSets | length' "$R53_DUMP")
echo ""
echo "Processing $TOTAL Route53 record sets..."
echo ""

# ── Step 2: Build set of existing TF records to skip duplicates ───────────────
# Uses a temp file + grep instead of bash 4 associative arrays for portability.

EXISTING_RECORDS_FILE=$(mktemp)
trap "rm -f $EXISTING_RECORDS_FILE" EXIT

EXISTING_COUNT=0
if [ -n "$EXISTING_TF" ] && [ -f "$EXISTING_TF" ]; then
    echo "Reading existing Terraform records from $EXISTING_TF..."
    # Extract (type, name) tuples from existing TF to detect duplicates.
    # Match on type+name only (not content) because Route53 values may differ
    # from desired Cloudflare state (e.g. CDN CNAMEs vs direct backend targets).
    awk '
        /^resource "cloudflare_record"/ { in_resource=1; r_name=""; r_type="" }
        in_resource && /name[[:space:]]*=/ {
            gsub(/.*name[[:space:]]*=[[:space:]]*"/, ""); gsub(/".*/, ""); r_name=tolower($0)
        }
        in_resource && /type[[:space:]]*=/ {
            gsub(/.*type[[:space:]]*=[[:space:]]*"/, ""); gsub(/".*/, ""); r_type=$0
        }
        in_resource && /^}/ {
            if (r_name != "" && r_type != "") {
                print r_type "|" r_name
            }
            in_resource=0
        }
    ' "$EXISTING_TF" > "$EXISTING_RECORDS_FILE"
    EXISTING_COUNT=$(wc -l < "$EXISTING_RECORDS_FILE" | tr -d ' ')
    echo "Found ${EXISTING_COUNT} existing record(s) in TF"
    echo ""
fi

# Check if a record exists in the existing TF file
record_exists_in_tf() {
    local key="$1"
    grep -qxF "$key" "$EXISTING_RECORDS_FILE" 2>/dev/null
}

# ── Step 3: Helper functions ──────────────────────────────────────────────────

# Strip trailing dot and zone suffix to get Terraform "name" field
# e.g. "ashburn.8x8.vc." -> "ashburn", "8x8.vc." -> "8x8.vc"
r53_name_to_tf_name() {
    local fqdn="$1"
    # Strip trailing dot
    fqdn="${fqdn%.}"
    # If it's the zone apex, return the domain itself
    if [[ "$fqdn" == "$DOMAIN" ]]; then
        echo "$DOMAIN"
    else
        # Strip the zone suffix
        echo "${fqdn%.${DOMAIN}}"
    fi
}

# Sanitize a name for use as a Terraform resource identifier
# e.g. "_acme-challenge.ai.stage" -> "acme_challenge_ai_stage"
sanitize_tf_id() {
    local name="$1"
    local type="$2"
    # Replace wildcard
    name="${name//\*/wildcard}"
    # Replace dots, hyphens, and other non-alphanumeric chars with underscore
    name=$(echo "$name" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//' | sed 's/_$//')
    echo "$(echo "$type" | tr '[:upper:]' '[:lower:]')_$(echo "$name" | tr '[:upper:]' '[:lower:]')"
}

# Strip outer quotes from TXT values and concatenate multi-string values
clean_txt_value() {
    local val="$1"
    # Route53 TXT values are wrapped in quotes: "value"
    # Multi-string: "part1" "part2" -> part1part2
    val=$(echo "$val" | sed 's/^"//; s/"$//; s/" "//g')
    echo "$val"
}

# Route53 uses \052 for wildcard
unescape_r53_name() {
    local name="$1"
    echo "${name//\\052/*}"
}

# ── Step 4: Main processing loop ─────────────────────────────────────────────

TF_CONTENT=""
WARNINGS=""
IMPORT_CONTENT="#!/bin/bash\nset -e\n\n# Import commands for records that already exist in Cloudflare.\n# Run from the record/ directory:\n#   cd 8x8_Inc./8x8.vc/record && bash ../../../${IMPORT_OUTPUT}\n#\n# Zone ID: 5588194be08840a767677b7636edce80\n# Each command: terragrunt import <resource_address> <zone_id>/<record_id>\n# You'll need to look up the CF record IDs via API or CF dashboard.\n\n"

for i in $(seq 0 $((TOTAL - 1))); do
    RECORD=$(jq ".ResourceRecordSets[$i]" "$R53_DUMP")
    RAW_NAME=$(echo "$RECORD" | jq -r '.Name')
    TYPE=$(echo "$RECORD" | jq -r '.Type')
    HAS_ALIAS=$(echo "$RECORD" | jq 'has("AliasTarget")')
    SET_ID=$(echo "$RECORD" | jq -r '.SetIdentifier // empty')
    TTL=$(echo "$RECORD" | jq -r '.TTL // 1')

    # Unescape Route53 wildcard encoding
    RAW_NAME=$(unescape_r53_name "$RAW_NAME")
    TF_NAME=$(r53_name_to_tf_name "$RAW_NAME")

    # ── Skip SOA ──
    if [[ "$TYPE" == "SOA" ]]; then
        SKIPPED_SOA_NS=$((SKIPPED_SOA_NS + 1))
        continue
    fi

    # ── Skip apex NS ──
    if [[ "$TYPE" == "NS" && "$RAW_NAME" == "${DOMAIN}." ]]; then
        SKIPPED_SOA_NS=$((SKIPPED_SOA_NS + 1))
        continue
    fi

    # ── Skip NAPTR (not supported by Cloudflare) ──
    if [[ "$TYPE" == "NAPTR" ]]; then
        SKIPPED_NAPTR=$((SKIPPED_NAPTR + 1))
        WARNINGS+="NAPTR_UNSUPPORTED: ${RAW_NAME} ${TYPE}"$'\n'
        WARNINGS+="  Cloudflare does not support NAPTR records."$'\n'
        WARNINGS+="  Values: $(echo "$RECORD" | jq -c '[.ResourceRecords[].Value]')"$'\n'
        WARNINGS+=""$'\n'
        continue
    fi

    # ── Warn on alias records ──
    if [[ "$HAS_ALIAS" == "true" ]]; then
        WARNED_ALIAS=$((WARNED_ALIAS + 1))
        ALIAS_TARGET=$(echo "$RECORD" | jq -r '.AliasTarget.DNSName')
        WARNINGS+="ALIAS_RECORD: ${RAW_NAME} ${TYPE} -> ${ALIAS_TARGET}"$'\n'
        if [ -n "$SET_ID" ]; then
            WARNINGS+="  Routing policy: SetIdentifier=\"${SET_ID}\""$'\n'
            # Extract routing details
            WEIGHT=$(echo "$RECORD" | jq -r '.Weight // empty')
            REGION=$(echo "$RECORD" | jq -r '.Region // empty')
            FAILOVER=$(echo "$RECORD" | jq -r '.Failover // empty')
            GEO=$(echo "$RECORD" | jq -c '.GeoLocation // empty')
            [ -n "$WEIGHT" ] && WARNINGS+="  Weight: ${WEIGHT}"$'\n'
            [ -n "$REGION" ] && WARNINGS+="  Region (latency): ${REGION}"$'\n'
            [ -n "$FAILOVER" ] && WARNINGS+="  Failover: ${FAILOVER}"$'\n'
            [ -n "$GEO" ] && [ "$GEO" != "" ] && WARNINGS+="  GeoLocation: ${GEO}"$'\n'
        fi
        WARNINGS+="  Needs manual conversion - Route53 alias has no direct Cloudflare equivalent."$'\n'
        WARNINGS+=""$'\n'
        continue
    fi

    # ── Warn on routing-policy records (non-alias) ──
    if [ -n "$SET_ID" ]; then
        WARNED_ROUTING=$((WARNED_ROUTING + 1))
        WARNINGS+="ROUTING_POLICY: ${RAW_NAME} ${TYPE} SetIdentifier=\"${SET_ID}\""$'\n'
        VALUES=$(echo "$RECORD" | jq -c '[.ResourceRecords[].Value]')
        WARNINGS+="  Values: ${VALUES}"$'\n'
        WEIGHT=$(echo "$RECORD" | jq -r '.Weight // empty')
        REGION=$(echo "$RECORD" | jq -r '.Region // empty')
        GEO=$(echo "$RECORD" | jq -c '.GeoLocation // empty')
        [ -n "$WEIGHT" ] && WARNINGS+="  Weight: ${WEIGHT}"$'\n'
        [ -n "$REGION" ] && WARNINGS+="  Region (latency): ${REGION}"$'\n'
        [ -n "$GEO" ] && [ "$GEO" != "" ] && WARNINGS+="  GeoLocation: ${GEO}"$'\n'
        WARNINGS+="  Needs manual review - routing policies don't map directly to Cloudflare."$'\n'
        WARNINGS+=""$'\n'
        continue
    fi

    # ── Process standard records ──

    # Get values array
    VALUES=$(echo "$RECORD" | jq -c '.ResourceRecords // []')
    VALUE_COUNT=$(echo "$VALUES" | jq 'length')

    if [[ "$VALUE_COUNT" -eq 0 ]]; then
        continue
    fi

    # TTL: use 1 (automatic) for TTLs <= 60 or 300 (common Route53 default)
    TF_TTL="$TTL"
    if [[ "$TTL" -le 60 ]] || [[ "$TTL" -eq 300 ]]; then
        TF_TTL=1
    fi

    # Handle SRV records specially
    if [[ "$TYPE" == "SRV" ]]; then
        # SRV name format: _service._proto.name.domain.
        # Parse service, proto, and remainder from the record name
        SRV_FQDN="${RAW_NAME%.}"
        # Extract _service._proto prefix
        SRV_SERVICE=$(echo "$SRV_FQDN" | cut -d. -f1)
        SRV_PROTO=$(echo "$SRV_FQDN" | cut -d. -f2)
        SRV_REST=$(echo "$SRV_FQDN" | cut -d. -f3-)
        # The TF name for SRV is the full _service._proto.host form relative to zone
        SRV_TF_NAME="${SRV_SERVICE}.${SRV_PROTO}"
        if [[ "$SRV_REST" != "$DOMAIN" ]]; then
            SRV_TF_NAME="${SRV_SERVICE}.${SRV_PROTO}.${SRV_REST%.${DOMAIN}}"
        fi

        for v in $(seq 0 $((VALUE_COUNT - 1))); do
            VALUE=$(echo "$VALUES" | jq -r ".[$v].Value")
            # SRV value: "priority weight port target"
            SRV_PRIORITY=$(echo "$VALUE" | awk '{print $1}')
            SRV_WEIGHT=$(echo "$VALUE" | awk '{print $2}')
            SRV_PORT=$(echo "$VALUE" | awk '{print $3}')
            SRV_TARGET=$(echo "$VALUE" | awk '{print $4}' | sed 's/\.$//')

            RESOURCE_ID=$(sanitize_tf_id "${SRV_TF_NAME}" "srv")
            [ "$VALUE_COUNT" -gt 1 ] && RESOURCE_ID="${RESOURCE_ID}_${v}"

            # Check existing
            LOOKUP_KEY="${TYPE}|$(echo "$SRV_TF_NAME" | tr '[:upper:]' '[:lower:]')"
            if record_exists_in_tf "$LOOKUP_KEY"; then
                SKIPPED_EXISTING=$((SKIPPED_EXISTING + 1))
                continue
            fi

            TF_CONTENT+="resource \"cloudflare_record\" \"${RESOURCE_ID}\" {"$'\n'
            TF_CONTENT+="  name = \"${SRV_TF_NAME}\""$'\n'
            TF_CONTENT+="  type = \"SRV\""$'\n'
            TF_CONTENT+="  ttl  = ${TF_TTL}"$'\n'
            TF_CONTENT+=""$'\n'
            TF_CONTENT+="  data {"$'\n'
            TF_CONTENT+="    priority = ${SRV_PRIORITY}"$'\n'
            TF_CONTENT+="    weight   = ${SRV_WEIGHT}"$'\n'
            TF_CONTENT+="    port     = ${SRV_PORT}"$'\n'
            TF_CONTENT+="    target   = \"${SRV_TARGET}\""$'\n'
            TF_CONTENT+="  }"$'\n'
            TF_CONTENT+=""$'\n'
            TF_CONTENT+="  zone_id = var.zone_id"$'\n'
            TF_CONTENT+="}"$'\n'
            TF_CONTENT+=""$'\n'
            CREATED=$((CREATED + 1))
        done
        continue
    fi

    # Handle all other record types (A, AAAA, CNAME, TXT, MX, NS subdomain, CAA, PTR)
    for v in $(seq 0 $((VALUE_COUNT - 1))); do
        VALUE=$(echo "$VALUES" | jq -r ".[$v].Value")

        # Clean up value based on type
        CONTENT="$VALUE"
        case "$TYPE" in
            CNAME|NS|MX|PTR)
                # Strip trailing dot
                CONTENT="${CONTENT%.}"
                ;;
            TXT)
                # Strip outer quotes
                CONTENT=$(clean_txt_value "$CONTENT")
                ;;
        esac

        # For MX, extract priority from the value (Route53 has it in ResourceRecords)
        MX_PRIORITY=""
        if [[ "$TYPE" == "MX" ]]; then
            MX_PRIORITY=$(echo "$VALUE" | awk '{print $1}')
            CONTENT=$(echo "$VALUE" | awk '{$1=""; print}' | sed 's/^ //' | sed 's/\.$//')
        fi

        # Check if record already exists in TF
        LOOKUP_KEY="${TYPE}|$(echo "$TF_NAME" | tr '[:upper:]' '[:lower:]')"
        if record_exists_in_tf "$LOOKUP_KEY"; then
            SKIPPED_EXISTING=$((SKIPPED_EXISTING + 1))
            continue
        fi

        # Generate resource ID
        RESOURCE_ID=$(sanitize_tf_id "$TF_NAME" "${TYPE}")
        [ "$VALUE_COUNT" -gt 1 ] && RESOURCE_ID="${RESOURCE_ID}_${v}"

        # Determine proxied status - default false for safety
        PROXIED="false"

        # Build TF block
        TF_CONTENT+="resource \"cloudflare_record\" \"${RESOURCE_ID}\" {"$'\n'
        TF_CONTENT+="  name    = \"${TF_NAME}\""$'\n'
        TF_CONTENT+="  proxied = ${PROXIED}"$'\n'
        TF_CONTENT+="  ttl     = ${TF_TTL}"$'\n'
        TF_CONTENT+="  type    = \"${TYPE}\""$'\n'

        # Escape content for HCL (backslashes and quotes)
        ESCAPED_CONTENT=$(echo "$CONTENT" | sed 's/\\/\\\\/g; s/"/\\"/g')
        TF_CONTENT+="  content = \"${ESCAPED_CONTENT}\""$'\n'

        if [ -n "$MX_PRIORITY" ]; then
            TF_CONTENT+="  priority = ${MX_PRIORITY}"$'\n'
        fi

        TF_CONTENT+="  zone_id = var.zone_id"$'\n'
        TF_CONTENT+="}"$'\n'
        TF_CONTENT+=""$'\n'
        CREATED=$((CREATED + 1))
    done
done

# ── Step 5: Write output files ────────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
    echo "=== DRY RUN MODE ==="
    echo ""
    echo "Would write $CREATED Terraform resources to $TF_OUTPUT"
    echo ""
    if [ -n "$TF_CONTENT" ]; then
        echo "--- Preview (first 100 lines) ---"
        echo "$TF_CONTENT" | head -100
        LINE_COUNT=$(echo "$TF_CONTENT" | wc -l)
        if [ "$LINE_COUNT" -gt 100 ]; then
            echo "... ($LINE_COUNT total lines)"
        fi
    fi
else
    if [ -n "$TF_CONTENT" ]; then
        echo "$TF_CONTENT" > "$TF_OUTPUT"
        echo "Wrote Terraform resources to $TF_OUTPUT"
    fi
fi

if [ -n "$WARNINGS" ]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "--- Warnings ---"
        echo "$WARNINGS"
    else
        echo "$WARNINGS" > "$WARNINGS_OUTPUT"
        echo "Wrote warnings to $WARNINGS_OUTPUT"
    fi
fi

# ── Step 6: Summary ──────────────────────────────────────────────────────────

echo ""
echo "========================================"
echo "Migration Summary for $DOMAIN"
echo "========================================"
echo "Total Route53 record sets:        $TOTAL"
echo "Terraform resources generated:    $CREATED"
echo "Skipped (already in TF):          $SKIPPED_EXISTING"
echo "Skipped (SOA/apex NS):            $SKIPPED_SOA_NS"
echo "Skipped (NAPTR - unsupported):    $SKIPPED_NAPTR"
echo "Warned (alias records):           $WARNED_ALIAS"
echo "Warned (routing policies):        $WARNED_ROUTING"
echo "========================================"
echo ""

if [ "$WARNED_ALIAS" -gt 0 ] || [ "$WARNED_ROUTING" -gt 0 ] || [ "$SKIPPED_NAPTR" -gt 0 ]; then
    echo "Review ${WARNINGS_OUTPUT} for records needing manual attention."
    echo ""
fi

if [[ "$DRY_RUN" != "true" ]] && [ "$CREATED" -gt 0 ]; then
    echo "Next steps:"
    echo "  1. Review generated TF in $TF_OUTPUT"
    echo "  2. Copy/append to 8x8_Inc./8x8.vc/record/cloudflare_record.tf"
    echo "  3. Run 'terragrunt fmt' in the record/ directory"
    echo "  4. Create PR and let Atlantis plan"
    echo "  5. Review the plan output carefully before applying"
fi
