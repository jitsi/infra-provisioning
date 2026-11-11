#!/bin/bash

# grid-scale.sh - Dynamic Selenium Grid scaling via Consul KV and OCI instance pools
# Subcommands: request, release, reconcile (scaledown is the old name), github-watch, status
#
# The pool is sized to the minimum plus the slots of the active reservations (one slot is one node,
# the grid nodes take one session each; reservations sharing a group count once), up to a maximum.
# request reserves and grows the pool, reconcile (run every couple of minutes by the
# selenium-grid-reconcile job) grows it and shrinks it back once the grid is idle, github-watch
# reserves for the PR tests while they have runs on GitHub.
#
# CI hosts without OCI access reserve by writing the Consul key
# selenium-grid/<grid>/reservations/<id> with {"slots": N, "arch": "arm", "created_at": <epoch>,
# "group": "<optional>", "ttl": <optional seconds>}, and release by deleting it and writing the epoch
# to selenium-grid/<grid>/last_release_at. reconcile then sizes the pool.
#
# The minimum, maximum, cooldown and ttl of a grid are in selenium-grid/<grid>/config, e.g.
# {"min_pool_size_arm": 4, "max_pool_size_arm": 50}. reconcile and github-watch leave alone a grid
# without that key.

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
[ -z "$GRID_WAIT_TIMEOUT" ] && GRID_WAIT_TIMEOUT=900
[ -z "$GRID_MIN_POOL_SIZE_X86" ] && GRID_MIN_POOL_SIZE_X86=1
[ -z "$GRID_MIN_POOL_SIZE_ARM" ] && GRID_MIN_POOL_SIZE_ARM=4
# The reservations can be written by any CI host that reaches Consul, so the pool never grows above this
[ -z "$GRID_MAX_POOL_SIZE_X86" ] && GRID_MAX_POOL_SIZE_X86=10
[ -z "$GRID_MAX_POOL_SIZE_ARM" ] && GRID_MAX_POOL_SIZE_ARM=50
[ -z "$GRID_COOLDOWN_SECONDS" ] && GRID_COOLDOWN_SECONDS=600
[ -z "$GRID_POLL_INTERVAL" ] && GRID_POLL_INTERVAL=15
# A reservation older than this is left over from a build that never released it and is ignored
[ -z "$GRID_RESERVATION_TTL" ] && GRID_RESERVATION_TTL=7200
# github-watch: the PR test runs of these repos get GRID_WATCH_SLOTS slots (a PR test peaks at 16 sessions)
[ -z "$GRID_WATCH_OWNER" ] && GRID_WATCH_OWNER=jitsi
[ -z "$GRID_WATCH_REPOS" ] && GRID_WATCH_REPOS="jitsi-meet lib-jitsi-meet jicofo jitsi-videobridge jicoco"
[ -z "$GRID_WATCH_WORKFLOW" ] && GRID_WATCH_WORKFLOW=pr-torture-trigger.yml
[ -z "$GRID_WATCH_SLOTS" ] && GRID_WATCH_SLOTS=16
[ -z "$GRID_WATCH_GROUP" ] && GRID_WATCH_GROUP=pr-torture
[ -z "$GRID_WATCH_TTL" ] && GRID_WATCH_TTL=600

###############################################################################
# Helper functions
###############################################################################

# Sets GRID_HAS_CONFIG=true when the grid has a config in Consul
get_consul_config() {
    local config_json
    GRID_HAS_CONFIG=false
    config_json=$(curl -s -f "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/config?raw" 2>/dev/null || echo "")
    if [ -n "$config_json" ] && [ "$config_json" != "null" ]; then
        GRID_HAS_CONFIG=true
        local val
        val=$(echo "$config_json" | jq -r '.min_pool_size_x86 // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MIN_POOL_SIZE_X86="$val"
        val=$(echo "$config_json" | jq -r '.min_pool_size_arm // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MIN_POOL_SIZE_ARM="$val"
        val=$(echo "$config_json" | jq -r '.cooldown_seconds // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_COOLDOWN_SECONDS="$val"
        val=$(echo "$config_json" | jq -r '.reservation_ttl // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_RESERVATION_TTL="$val"
        val=$(echo "$config_json" | jq -r '.max_pool_size_x86 // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MAX_POOL_SIZE_X86="$val"
        val=$(echo "$config_json" | jq -r '.max_pool_size_arm // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_MAX_POOL_SIZE_ARM="$val"
    fi
    # The last test above fails when its key is missing, which set -e would take as a failure
    return 0
}

# The reservations as a JSON array of {key, slots, arch, created_at, group?, ttl?}, expired ones included
get_reservations() {
    local keys_json
    keys_json=$(curl -s "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/reservations/?recurse" 2>/dev/null || echo "")
    # Consul answers 404 with an empty body when there are no keys
    if [ -z "$keys_json" ] || [ "$keys_json" = "null" ]; then
        echo "[]"
        return
    fi
    echo "$keys_json" | jq -c '[.[] | {key: .Key} + (.Value | @base64d | fromjson)]' 2>/dev/null || echo "[]"
}

# The reservations that are not older than their ttl, or GRID_RESERVATION_TTL when they have none
get_active_reservations() {
    get_reservations | jq -c --argjson now "$(date +%s)" --argjson ttl "$GRID_RESERVATION_TTL" \
        '[.[] | select(($now - (.created_at // 0)) < (.ttl // $ttl))]'
}

# Reservations with the same group are from builds that take turns on the grid (e.g. behind one lock),
# so a group counts once, with its largest reservation, however many of its builds are waiting.
get_total_reserved_slots() {
    local arch="${1:-x86}"
    get_active_reservations | jq --arg arch "$arch" '
        [.[] | select(.arch == $arch)]
        | ([.[] | select(.group == null) | .slots] | add // 0)
          + ([.[] | select(.group != null)] | group_by(.group) | map(map(.slots) | max) | add // 0)'
}

get_reservation_count() {
    get_active_reservations | jq 'length'
}

delete_expired_reservations() {
    local key
    for key in $(get_reservations | jq -r --argjson now "$(date +%s)" --argjson ttl "$GRID_RESERVATION_TTL" \
            '.[] | select(($now - (.created_at // 0)) >= (.ttl // $ttl)) | .key'); do
        echo "Deleting expired reservation $key"
        curl -s -X DELETE "$CONSUL_URL/v1/kv/$key" >/dev/null
    done
}

# Prints the busy and queued session counts of the grid as "<sessions> <queued>", nothing when the
# hub can't be reached
get_grid_sessions() {
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"query":"{ grid { sessionCount, sessionQueueSize } }"}' \
        "$GRID_URL/graphql" 2>/dev/null || echo "")
    echo "$response" | jq -r '.data.grid | "\(.sessionCount) \(.sessionQueueSize)"' 2>/dev/null || true
}

get_pool_ids() {
    local tmp_state
    tmp_state=$(mktemp)
    if ! oci os object get --bucket-name "$S3_STATE_BUCKET" --name "$S3_STATE_KEY_IP" --region "$ORACLE_REGION" --file "$tmp_state" 2>/dev/null; then
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
        --data '{"query":"{ nodesInfo { nodes { id, status } } }"}' \
        "$GRID_URL/graphql" 2>/dev/null || echo "")
    if [ -z "$response" ]; then
        echo 0
        return
    fi
    echo "$response" | jq '[.data.nodesInfo.nodes[] | select(.status == "UP")] | length' 2>/dev/null || echo 0
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
    echo "WARNING: Timed out waiting for $desired UP nodes after ${timeout}s"
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
    echo "Grid: $GRID_NAME, Build: $BUILD_TAG, Slots: $GRID_SLOTS_REQUESTED, Arch: $arch, Group: ${GRID_RESERVATION_GROUP:-none}"

    get_consul_config

    # Write reservation to Consul KV
    local reservation_json
    reservation_json=$(jq -n \
        --argjson slots "$GRID_SLOTS_REQUESTED" \
        --arg arch "$arch" \
        --arg group "$GRID_RESERVATION_GROUP" \
        --argjson created_at "$(date +%s)" \
        '{slots: $slots, arch: $arch, created_at: $created_at} + (if $group == "" then {} else {group: $group} end)')

    local kv_key="$CONSUL_KV_PREFIX/reservations/$BUILD_TAG"
    curl -s -X PUT -d "$reservation_json" "$CONSUL_URL/v1/kv/$kv_key" >/dev/null
    echo "Reservation written to Consul: $kv_key"

    # Calculate total desired size
    local total_reserved
    total_reserved=$(get_total_reserved_slots "$arch")
    echo "Total reserved $arch slots: $total_reserved"

    # The minimum is for the users of the grid that make no reservations (e.g. the PR tests), so the
    # reservations come on top of it
    local min_size
    if [ "$arch" = "arm" ]; then
        min_size=$GRID_MIN_POOL_SIZE_ARM
    else
        min_size=$GRID_MIN_POOL_SIZE_X86
    fi
    local total_desired=$((min_size + total_reserved))

    # Fetch pool IDs from terraform state
    get_pool_ids

    # Resize pool if needed
    local pool_id
    if [ "$arch" = "arm" ]; then
        pool_id=$NODE_POOL_ID_ARM
    else
        pool_id=$NODE_POOL_ID_X86
    fi

    # Only grow here: shrinking terminates nodes that may be running sessions, it is left to scaledown
    local current_size
    current_size=$(get_pool_size "$pool_id")
    if [ "$current_size" -lt "$total_desired" ] 2>/dev/null; then
        resize_pool "$pool_id" "$total_desired"
    else
        echo "Pool size $current_size already covers the $total_desired needed, not resizing"
    fi

    # Wait for nodes to be UP. A scale-up takes ~8 minutes. When it takes longer, carry on with the
    # nodes there are: the tests then queue on the grid instead of not running at all.
    if ! wait_for_nodes "$total_desired" "$GRID_WAIT_TIMEOUT"; then
        echo "Continuing with $(get_grid_node_count) UP nodes"
    fi
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

# Sizes the ARM pool to what the grid needs: the minimum plus the reservations, and at least the
# running and queued sessions, so a user that made no reservation still gets nodes (one scale-up
# later). Grows right away, shrinks only an idle grid once the cooldown since the last release passed.
# Only manages a grid that has a config in Consul.
cmd_reconcile() {
    echo "=== Grid Reconcile ==="
    echo "Grid: $GRID_NAME"

    get_consul_config
    if [ "$GRID_HAS_CONFIG" != "true" ]; then
        echo "No $CONSUL_KV_PREFIX/config in Consul, not managing grid $GRID_NAME"
        return 0
    fi

    delete_expired_reservations

    local reserved
    reserved=$(get_total_reserved_slots arm)

    local sessions busy=0 queued=0 hub_known=false
    sessions=$(get_grid_sessions)
    if [[ "$sessions" =~ ^[0-9]+\ [0-9]+$ ]]; then
        hub_known=true
        read -r busy queued <<< "$sessions"
    fi

    local target=$((GRID_MIN_POOL_SIZE_ARM + reserved))
    if [ $((busy + queued)) -gt "$target" ]; then
        target=$((busy + queued))
    fi
    if [ "$target" -gt "$GRID_MAX_POOL_SIZE_ARM" ]; then
        echo "Capping $target at the maximum $GRID_MAX_POOL_SIZE_ARM"
        target=$GRID_MAX_POOL_SIZE_ARM
    fi

    get_pool_ids
    if [ -z "$NODE_POOL_ID_ARM" ] || [ "$NODE_POOL_ID_ARM" = "null" ]; then
        echo "No ARM pool for grid $GRID_NAME"
        return 0
    fi
    local current
    current=$(get_pool_size "$NODE_POOL_ID_ARM")
    if ! [[ "$current" =~ ^[0-9]+$ ]]; then
        echo "Could not read the size of pool $NODE_POOL_ID_ARM"
        return 1
    fi
    echo "Pool $current, target $target (min $GRID_MIN_POOL_SIZE_ARM, reserved $reserved, sessions $busy, queued $queued)"

    if [ "$current" -lt "$target" ]; then
        resize_pool "$NODE_POOL_ID_ARM" "$target"
        return 0
    fi
    if [ "$current" -eq "$target" ]; then
        return 0
    fi

    # The pool shrinks by terminating nodes without draining them, so only shrink an idle grid
    if [ "$hub_known" != "true" ]; then
        echo "Could not read the sessions of $GRID_URL, not shrinking"
        return 0
    fi
    if [ "$busy" -ne 0 ] || [ "$queued" -ne 0 ]; then
        echo "Grid not idle, not shrinking"
        return 0
    fi
    local last_release
    last_release=$(curl -s -f "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_release_at?raw" 2>/dev/null || echo "")
    if [[ "$last_release" =~ ^[0-9]+$ ]]; then
        local elapsed=$(($(date +%s) - last_release))
        if [ "$elapsed" -lt "$GRID_COOLDOWN_SECONDS" ]; then
            echo "Cooldown active: ${elapsed}s / ${GRID_COOLDOWN_SECONDS}s since last release, not shrinking"
            return 0
        fi
    fi

    resize_pool "$NODE_POOL_ID_ARM" "$target"
}

# Prints an installation token of the GitHub App GITHUB_APP_ID (private key in GITHUB_APP_KEY_FILE)
# that can only read the Actions of the watched repos
github_app_token() {
    local now header payload signature jwt installation repos
    b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
    now=$(date +%s)
    header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
    payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$GITHUB_APP_ID" | b64url)
    signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$GITHUB_APP_KEY_FILE" | b64url)
    jwt="$header.$payload.$signature"
    installation=$(curl -s -f -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$GRID_WATCH_OWNER/installation" | jq -r .id)
    repos=$(printf '%s\n' $GRID_WATCH_REPOS | jq -R . | jq -sc .)
    curl -s -f -X POST -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
        --data "{\"repositories\":$repos,\"permissions\":{\"actions\":\"read\"}}" \
        "https://api.github.com/app/installations/$installation/access_tokens" | jq -r .token
}

# Keeps a reservation for the PR tests while any of the watched repos has a PR test run waiting or
# running. The PR tests run one at a time, so it is one reservation, refreshed on every call and
# expiring GRID_WATCH_TTL seconds after the last one that saw a run.
cmd_github_watch() {
    echo "=== GitHub PR test watch ==="
    echo "Grid: $GRID_NAME, repos: $GRID_WATCH_REPOS"

    get_consul_config
    if [ "$GRID_HAS_CONFIG" != "true" ]; then
        echo "No $CONSUL_KV_PREFIX/config in Consul, not managing grid $GRID_NAME"
        return 0
    fi

    # Keep the token out of the trace
    { set +x; } 2>/dev/null
    local token="$GITHUB_TOKEN"
    if [ -z "$token" ] && [ -n "$GITHUB_APP_ID" ] && [ -n "$GITHUB_APP_KEY_FILE" ]; then
        token=$(github_app_token || echo "")
    fi
    if [ -z "$token" ]; then
        echo "No GitHub token, leaving the PR test reservation as it is"
        set -x
        return 0
    fi

    local runs=0 repo status count failed=false
    for repo in $GRID_WATCH_REPOS; do
        for status in queued in_progress; do
            if ! count=$(curl -s -f -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/$GRID_WATCH_OWNER/$repo/actions/workflows/$GRID_WATCH_WORKFLOW/runs?status=$status&per_page=1" \
                    | jq -er .total_count); then
                echo "Could not read the $status runs of $repo"
                failed=true
                continue
            fi
            echo "$repo: $count $status"
            runs=$((runs + count))
        done
    done
    set -x

    local kv_key="$CONSUL_KV_PREFIX/reservations/github-$GRID_WATCH_GROUP"
    if [ "$runs" -gt 0 ]; then
        local reservation_json
        reservation_json=$(jq -n --argjson slots "$GRID_WATCH_SLOTS" --arg group "$GRID_WATCH_GROUP" \
            --argjson created_at "$(date +%s)" --argjson ttl "$GRID_WATCH_TTL" \
            '{slots: $slots, arch: "arm", group: $group, created_at: $created_at, ttl: $ttl}')
        curl -s -X PUT -d "$reservation_json" "$CONSUL_URL/v1/kv/$kv_key" >/dev/null
        echo "$runs PR test runs, reserved $GRID_WATCH_SLOTS slots: $kv_key"
    elif [ "$failed" = "true" ]; then
        echo "No runs seen but some repos could not be read, leaving $kv_key as it is"
    elif curl -s -f "$CONSUL_URL/v1/kv/$kv_key" >/dev/null 2>&1; then
        curl -s -X DELETE "$CONSUL_URL/v1/kv/$kv_key" >/dev/null
        curl -s -X PUT -d "$(date +%s)" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_release_at" >/dev/null
        echo "No PR test runs, released $kv_key"
    else
        echo "No PR test runs"
    fi
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
    reconcile|scaledown)
        cmd_reconcile
        ;;
    github-watch)
        cmd_github_watch
        ;;
    status)
        cmd_status
        ;;
    *)
        echo "Usage: $0 {request|release|reconcile|github-watch|status}"
        exit 1
        ;;
esac
