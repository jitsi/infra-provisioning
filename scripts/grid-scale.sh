#!/bin/bash

# grid-scale.sh - Dynamic Selenium Grid scaling via Consul KV and OCI instance pools
# Subcommands: request, release, scaledown, status

set -e
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# Required variables
if [ -z "$ENVIRONMENT" ]; then
    echo "ERROR: No ENVIRONMENT set, exiting"
    exit 1
fi

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

set -x


if [ -z "$GRID_NAME" ]; then
    echo "ERROR: No GRID_NAME set, exiting"
    exit 1
fi

[ -z "$ORACLE_REGION" ] && ORACLE_REGION="$OCI_LOCAL_REGION"
[ -z "$ORACLE_REGION" ] && ORACLE_REGION="us-phoenix-1"

# Grid infrastructure environment (pools always live in torture-test)
[ -z "$GRID_ENVIRONMENT" ] && GRID_ENVIRONMENT="torture-test"

# Consul configuration (uses GRID_ENVIRONMENT since grid infra lives in torture-test)
OCI_LOCAL_DATACENTER="$GRID_ENVIRONMENT-$ORACLE_REGION"
CONSUL_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"
CONSUL_URL="https://$CONSUL_HOST"
CONSUL_KV_PREFIX="selenium-grid/$GRID_NAME"

# Grid URL (matches CNAME pattern from deploy-nomad-selenium-grid-hub.sh)
GRID_URL="https://${GRID_ENVIRONMENT}-${ORACLE_REGION}-${GRID_NAME}-grid.${TOP_LEVEL_DNS_ZONE_NAME}"

# S3 terraform state (matches create-selenium-grid-oracle.sh)
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$GRID_ENVIRONMENT"
S3_STATE_BASE="$GRID_ENVIRONMENT/grid/$GRID_NAME/components"
S3_STATE_KEY_IP="${S3_STATE_BASE}/terraform-ip.tfstate"

# Defaults
[ -z "$GRID_SLOTS_REQUESTED" ] && GRID_SLOTS_REQUESTED=1
[ -z "$GRID_WAIT_TIMEOUT" ] && GRID_WAIT_TIMEOUT=600
[ -z "$GRID_MIN_POOL_SIZE_X86" ] && GRID_MIN_POOL_SIZE_X86=1
[ -z "$GRID_MIN_POOL_SIZE_ARM" ] && GRID_MIN_POOL_SIZE_ARM=4
[ -z "$GRID_COOLDOWN_SECONDS" ] && GRID_COOLDOWN_SECONDS=600
[ -z "$GRID_POLL_INTERVAL" ] && GRID_POLL_INTERVAL=15

###############################################################################
# Helper functions
###############################################################################

get_consul_config() {
    local config_json
    config_json=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/config?raw" 2>/dev/null || echo "")
    if [ -n "$config_json" ] && [ "$config_json" != "null" ]; then
        local val
        val=$(echo "$config_json" | jq -r '.min_pool_size_x86 // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MIN_POOL_SIZE_X86="$val"
        val=$(echo "$config_json" | jq -r '.min_pool_size_arm // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MIN_POOL_SIZE_ARM="$val"
        val=$(echo "$config_json" | jq -r '.cooldown_seconds // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_COOLDOWN_SECONDS="$val"
    fi
}

get_total_reserved_slots() {
    local arch="${1:-x86}"
    local keys_json
    keys_json=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/reservations/?recurse&raw" 2>/dev/null || echo "[]")
    if [ -z "$keys_json" ] || [ "$keys_json" = "null" ]; then
        echo 0
        return
    fi
    # Consul recurse returns array of KV entries; decode values and sum slots for matching arch
    local total
    total=$(echo "$keys_json" | jq -r "[.[] | .Value | @base64d | fromjson | select(.arch == \"$arch\") | .slots] | add // 0" 2>/dev/null)
    echo "${total:-0}"
}

get_reservation_count() {
    local keys_json
    keys_json=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/reservations/?keys" 2>/dev/null || echo "[]")
    if [ -z "$keys_json" ] || [ "$keys_json" = "null" ]; then
        echo 0
        return
    fi
    echo "$keys_json" | jq 'length'
}

get_pool_ids() {
    local tmp_state
    tmp_state=$(mktemp)
    oci os object get --bucket-name "$S3_STATE_BUCKET" --name "$S3_STATE_KEY_IP" --region "$ORACLE_REGION" --file "$tmp_state" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to fetch terraform state from S3" >&2
        rm -f "$tmp_state"
        return 1
    fi

    NODE_POOL_ID_X86=$(cat "$tmp_state" | jq -r '.resources[]
        | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node_x86")
        | .instances[0].attributes.id' 2>/dev/null)

    NODE_POOL_ID_ARM=$(cat "$tmp_state" | jq -r '.resources[]
        | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node_arm")
        | .instances[0].attributes.id' 2>/dev/null)

    # Fallback for non-nomad grids
    if [ -z "$NODE_POOL_ID_X86" ] || [ "$NODE_POOL_ID_X86" = "null" ]; then
        NODE_POOL_ID_X86=$(cat "$tmp_state" | jq -r '.resources[]
            | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node")
            | .instances[0].attributes.id' 2>/dev/null)
    fi

    rm -f "$tmp_state"
}

get_pool_size() {
    local pool_id="$1"
    if [ -z "$pool_id" ] || [ "$pool_id" = "null" ]; then
        echo 0
        return
    fi
    oci compute-management instance-pool get --instance-pool-id "$pool_id" --region "$ORACLE_REGION" 2>/dev/null | jq -r '.data.size'
}

resize_pool() {
    local pool_id="$1"
    local new_size="$2"
    if [ -z "$pool_id" ] || [ "$pool_id" = "null" ]; then
        echo "WARNING: No pool ID available, skipping resize"
        return 0
    fi
    local current_size
    current_size=$(get_pool_size "$pool_id")
    if [ "$current_size" = "$new_size" ]; then
        echo "Pool $pool_id already at size $new_size, no resize needed"
        return 0
    fi
    echo "Resizing pool $pool_id from $current_size to $new_size"
    oci compute-management instance-pool update --instance-pool-id "$pool_id" --size "$new_size" --region "$ORACLE_REGION" --force >/dev/null
}

get_grid_node_count() {
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"query":"{ nodesInfo { nodes { id, availability } } }"}' \
        "$GRID_URL/graphql" 2>/dev/null || echo "")
    if [ -z "$response" ]; then
        echo 0
        return
    fi
    echo "$response" | jq '[.data.nodesInfo.nodes[] | select(.availability == "UP")] | length' 2>/dev/null || echo 0
}

wait_for_nodes() {
    local desired="$1"
    local timeout="$2"
    local elapsed=0
    echo "Waiting for $desired UP nodes on grid $GRID_URL (timeout: ${timeout}s)"
    while [ $elapsed -lt "$timeout" ]; do
        local up_count
        up_count=$(get_grid_node_count)
        echo "  UP nodes: $up_count / $desired (elapsed: ${elapsed}s)"
        if [ "$up_count" -ge "$desired" ] 2>/dev/null; then
            echo "Grid has $up_count UP nodes, ready"
            return 0
        fi
        sleep "$GRID_POLL_INTERVAL"
        elapsed=$((elapsed + GRID_POLL_INTERVAL))
    done
    echo "ERROR: Timed out waiting for $desired UP nodes after ${timeout}s"
    return 1
}

###############################################################################
# Subcommands
###############################################################################

cmd_request() {
    if [ -z "$BUILD_TAG" ]; then
        echo "ERROR: BUILD_TAG is required for request"
        exit 1
    fi

    local arch="${GRID_ARCH:-arm}"

    echo "=== Grid Scale Request ==="
    echo "Grid: $GRID_NAME, Build: $BUILD_TAG, Slots: $GRID_SLOTS_REQUESTED, Arch: $arch"

    get_consul_config

    # Write reservation to Consul KV
    local reservation_json
    reservation_json=$(jq -n \
        --argjson slots "$GRID_SLOTS_REQUESTED" \
        --arg arch "$arch" \
        --argjson created_at "$(date +%s)" \
        '{slots: $slots, arch: $arch, created_at: $created_at}')

    local kv_key="$CONSUL_KV_PREFIX/reservations/$BUILD_TAG"
    curl -s -X PUT -d "$reservation_json" "$CONSUL_URL/v1/kv/$kv_key" >/dev/null
    echo "Reservation written to Consul: $kv_key"

    # Calculate total desired size
    local total_desired
    total_desired=$(get_total_reserved_slots "$arch")
    echo "Total reserved $arch slots: $total_desired"

    # Determine minimum pool size for this arch
    local min_size
    if [ "$arch" = "arm" ]; then
        min_size=$GRID_MIN_POOL_SIZE_ARM
    else
        min_size=$GRID_MIN_POOL_SIZE_X86
    fi
    # Desired is at least the minimum
    if [ "$total_desired" -lt "$min_size" ]; then
        total_desired=$min_size
    fi

    # Fetch pool IDs from terraform state
    get_pool_ids

    # Resize pool if needed
    local pool_id
    if [ "$arch" = "arm" ]; then
        pool_id=$NODE_POOL_ID_ARM
    else
        pool_id=$NODE_POOL_ID_X86
    fi

    resize_pool "$pool_id" "$total_desired"

    # Wait for nodes to be UP
    wait_for_nodes "$total_desired" "$GRID_WAIT_TIMEOUT"
}

cmd_release() {
    if [ -z "$BUILD_TAG" ]; then
        echo "ERROR: BUILD_TAG is required for release"
        exit 1
    fi

    echo "=== Grid Scale Release ==="
    echo "Grid: $GRID_NAME, Build: $BUILD_TAG"

    # Delete reservation from Consul KV
    local kv_key="$CONSUL_KV_PREFIX/reservations/$BUILD_TAG"
    curl -s -X DELETE "$CONSUL_URL/v1/kv/$kv_key" >/dev/null
    echo "Reservation deleted: $kv_key"

    # Write last_release_at timestamp
    curl -s -X PUT -d "$(date +%s)" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_release_at" >/dev/null
    echo "Updated last_release_at"
}

cmd_scaledown() {
    echo "=== Grid Scale Down Check ==="
    echo "Grid: $GRID_NAME"

    get_consul_config

    # Check for active reservations
    local reservation_count
    reservation_count=$(get_reservation_count)
    if [ "$reservation_count" -gt 0 ]; then
        echo "Active reservations: $reservation_count, skipping scale-down"
        return 0
    fi

    # Check cooldown
    local last_release
    last_release=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_release_at?raw" 2>/dev/null || echo "")
    if [ -n "$last_release" ] && [ "$last_release" != "null" ]; then
        local now
        now=$(date +%s)
        local elapsed=$((now - last_release))
        if [ "$elapsed" -lt "$GRID_COOLDOWN_SECONDS" ]; then
            echo "Cooldown active: ${elapsed}s / ${GRID_COOLDOWN_SECONDS}s since last release, skipping"
            return 0
        fi
    fi

    echo "No active reservations and cooldown elapsed, scaling ARM pool to minimum"

    # Fetch pool IDs from terraform state
    get_pool_ids

    # Only scale ARM pool to minimum; leave x86 pool unchanged
    if [ -n "$NODE_POOL_ID_ARM" ] && [ "$NODE_POOL_ID_ARM" != "null" ]; then
        resize_pool "$NODE_POOL_ID_ARM" "$GRID_MIN_POOL_SIZE_ARM"
    fi

    echo "Scale-down complete"
}

cmd_status() {
    echo "=== Grid Scale Status ==="
    echo "Grid: $GRID_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Region: $ORACLE_REGION"
    echo "Grid URL: $GRID_URL"
    echo ""

    get_consul_config
    echo "Config: min_x86=$GRID_MIN_POOL_SIZE_X86, min_arm=$GRID_MIN_POOL_SIZE_ARM, cooldown=${GRID_COOLDOWN_SECONDS}s"
    echo ""

    # Show reservations
    echo "--- Reservations ---"
    local keys_json
    keys_json=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/reservations/?recurse" 2>/dev/null || echo "")
    if [ -n "$keys_json" ] && [ "$keys_json" != "null" ]; then
        echo "$keys_json" | jq -r '.[] | "\(.Key): \(.Value | @base64d)"'
    else
        echo "(none)"
    fi
    echo ""

    echo "Total reserved x86 slots: $(get_total_reserved_slots x86)"
    echo "Total reserved ARM slots: $(get_total_reserved_slots arm)"
    echo ""

    # Last release
    local last_release
    last_release=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_release_at?raw" 2>/dev/null || echo "none")
    echo "Last release at: $last_release"
    echo ""

    # Pool info
    echo "--- Pool Info ---"
    get_pool_ids
    if [ -n "$NODE_POOL_ID_X86" ] && [ "$NODE_POOL_ID_X86" != "null" ]; then
        echo "x86 pool ID: $NODE_POOL_ID_X86"
        echo "x86 pool size: $(get_pool_size "$NODE_POOL_ID_X86")"
    else
        echo "x86 pool: not found"
    fi
    if [ -n "$NODE_POOL_ID_ARM" ] && [ "$NODE_POOL_ID_ARM" != "null" ]; then
        echo "ARM pool ID: $NODE_POOL_ID_ARM"
        echo "ARM pool size: $(get_pool_size "$NODE_POOL_ID_ARM")"
    else
        echo "ARM pool: not found"
    fi
    echo ""

    # Grid node status
    echo "--- Grid Nodes ---"
    local up_count
    up_count=$(get_grid_node_count)
    echo "UP nodes: $up_count"
}

###############################################################################
# Main
###############################################################################

SUBCOMMAND="${1:-status}"

case "$SUBCOMMAND" in
    request)
        cmd_request
        ;;
    release)
        cmd_release
        ;;
    scaledown)
        cmd_scaledown
        ;;
    status)
        cmd_status
        ;;
    *)
        echo "Usage: $0 {request|release|scaledown|status}"
        exit 1
        ;;
esac
