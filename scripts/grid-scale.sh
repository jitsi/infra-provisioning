#!/bin/bash

# grid-scale.sh - Dynamic Selenium Grid scaling via Consul KV and OCI instance pools
# Subcommands: request, release, reconcile (scaledown is the old name), github-watch, status
#
# The pool is sized to the slots of the active reservations (one slot is one node, the grid nodes
# take one session each; reservations sharing a group count once), at least the minimum and at most a
# maximum.
# request reserves and grows the pool, reconcile (run every couple of minutes by the
# selenium-grid-reconcile job) grows it and shrinks it back once the grid is idle, github-watch
# reserves for the PR tests while they have runs on GitHub.
#
# CI hosts without OCI access reserve by writing the Consul key
# selenium-grid/<grid>/reservations/<id> with {"slots": N, "arch": "arm", "created_at": <epoch>,
# "group": "<optional>", "ttl": <optional seconds>}, and release by deleting it and writing the epoch
# to selenium-grid/<grid>/last_release_at. reconcile then sizes the pool.
#
# The settings of a grid are in selenium-grid/<grid>/config, e.g. {"min_pool_size_arm": 0,
# "max_pool_size_arm": 50, "schedule": [{"days": "1-5", "from": "08:00", "to": "23:00", "min": 20}],
# "holidays": ["2026-12-24"]}. reconcile and github-watch leave alone a grid without that key.

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
# The nomad of the grid nodes (as in deploy-nomad-selenium-grid-node.sh)
[ -z "$NOMAD_ADDR" ] && NOMAD_ADDR="https://${GRID_ENVIRONMENT}-${ORACLE_REGION}-nomad.${TOP_LEVEL_DNS_ZONE_NAME}"

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
# reconcile shrinks only after the grid was idle this long, by at most GRID_SCALE_DOWN_STEP nodes per
# GRID_SCALE_DOWN_INTERVAL, and not below the peak sessions of the last GRID_PEAK_WINDOW seconds
[ -z "$GRID_IDLE_SECONDS" ] && GRID_IDLE_SECONDS=1800
[ -z "$GRID_SCALE_DOWN_STEP" ] && GRID_SCALE_DOWN_STEP=8
[ -z "$GRID_SCALE_DOWN_INTERVAL" ] && GRID_SCALE_DOWN_INTERVAL=900
[ -z "$GRID_PEAK_WINDOW" ] && GRID_PEAK_WINDOW=3600
# A reservation older than this is left over from a build that never released it and is ignored
[ -z "$GRID_RESERVATION_TTL" ] && GRID_RESERVATION_TTL=7200
# github-watch: the PR test runs of these repos get GRID_WATCH_SLOTS slots (a PR test peaks at 16 sessions)
[ -z "$GRID_WATCH_OWNER" ] && GRID_WATCH_OWNER=jitsi
[ -z "$GRID_WATCH_REPOS" ] && GRID_WATCH_REPOS="jitsi-meet lib-jitsi-meet jicofo jitsi-videobridge jicoco"
[ -z "$GRID_WATCH_WORKFLOW" ] && GRID_WATCH_WORKFLOW=pr-torture-trigger.yml
[ -z "$GRID_WATCH_SLOTS" ] && GRID_WATCH_SLOTS=16
[ -z "$GRID_WATCH_GROUP" ] && GRID_WATCH_GROUP=pr-torture
[ -z "$GRID_WATCH_TTL" ] && GRID_WATCH_TTL=600
# Runs created longer ago than this are not counted: GitHub can leave a run queued for days without
# ever starting a job, and such a run would keep the reservation forever. The longest measured wait of
# a PR test run for the PR test box is 3 hours.
[ -z "$GRID_WATCH_MAX_AGE" ] && GRID_WATCH_MAX_AGE=21600

###############################################################################
# Helper functions
###############################################################################

# Sets GRID_HAS_CONFIG=true when the grid has a config in Consul
get_consul_config() {
    local config_json
    GRID_HAS_CONFIG=false
    GRID_CONFIG_JSON="{}"
    config_json=$(curl -s -f "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/config?raw" 2>/dev/null || echo "")
    if [ -n "$config_json" ] && [ "$config_json" != "null" ]; then
        GRID_HAS_CONFIG=true
        GRID_CONFIG_JSON="$config_json"
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
        val=$(echo "$config_json" | jq -r '.idle_seconds // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_IDLE_SECONDS="$val"
        val=$(echo "$config_json" | jq -r '.scale_down_step // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_SCALE_DOWN_STEP="$val"
        val=$(echo "$config_json" | jq -r '.scale_down_interval // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_SCALE_DOWN_INTERVAL="$val"
        val=$(echo "$config_json" | jq -r '.peak_window // empty' 2>/dev/null)
        [ -n "$val" ] && GRID_PEAK_WINDOW="$val"
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

# The private IPs of the running instances of the given pools, one per line, from the private_ip
# freeform tag the nodes set on themselves. Fails when OCI can't be read.
get_pool_instance_ips() {
    local pool_ids compartment_id instances
    pool_ids=$(printf '%s\n' "$@" | grep -v -e '^$' -e '^null$' | jq -R . | jq -sc .)
    [ "$pool_ids" = "[]" ] && return 1
    compartment_id=$(oci compute-management instance-pool get --instance-pool-id "$(echo "$pool_ids" | jq -r '.[0]')" \
        --region "$ORACLE_REGION" 2>/dev/null | jq -r '.data."compartment-id"')
    if [ -z "$compartment_id" ] || [ "$compartment_id" = "null" ]; then
        return 1
    fi
    instances=$(oci compute instance list --compartment-id "$compartment_id" --lifecycle-state RUNNING --all \
        --region "$ORACLE_REGION" 2>/dev/null) || return 1
    # The CLI prints nothing when the compartment has no running instances
    [ -z "$instances" ] && return 0
    echo "$instances" | jq -r --argjson pools "$pool_ids" '.data[] | .["freeform-tags"]
        | select(.["oci:compute:instancepool"] as $p | $pools | index($p)) | .private_ip // empty'
}

# The running instances of the given pool as "<private ip> <instance ocid>" lines. Fails when OCI
# can't be read.
get_pool_instances() {
    local compartment_id instances
    compartment_id=$(oci compute-management instance-pool get --instance-pool-id "$1" \
        --region "$ORACLE_REGION" 2>/dev/null | jq -r '.data."compartment-id"')
    if [ -z "$compartment_id" ] || [ "$compartment_id" = "null" ]; then
        return 1
    fi
    instances=$(oci compute instance list --compartment-id "$compartment_id" --lifecycle-state RUNNING --all \
        --region "$ORACLE_REGION" 2>/dev/null) || return 1
    [ -z "$instances" ] && return 0
    echo "$instances" | jq -r --arg pool "$1" '.data[]
        | select(.["freeform-tags"]["oci:compute:instancepool"] == $pool and .["freeform-tags"].private_ip != null)
        | "\(.["freeform-tags"].private_ip) \(.id)"'
}

# The hub nodes with no session as "<node id> <node ip>" lines
get_idle_grid_nodes() {
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"query":"{ nodesInfo { nodes { id, uri, status, sessionCount } } }"}' \
        "$GRID_URL/graphql" 2>/dev/null \
        | jq -r '.data.nodesInfo.nodes[]? | select(.status == "UP" and .sessionCount == 0)
            | "\(.id) \(.uri | sub("^https?://"; "") | sub("[:/].*$"; ""))"' 2>/dev/null || true
}

# Stops the grid node allocation on the nomad client with IP $1 and keeps nomad from starting it
# again: a node drained on the hub exits, and nomad would restart it 15s later, so it registers with
# the hub again while its instance is still being terminated. Does nothing for a grid without nomad.
# Sets NOMAD_DRAINED_NODE to the nomad node it drained, empty when it drained none.
nomad_drain_client() {
    local nodes node_id
    NOMAD_DRAINED_NODE=""
    if ! nodes=$(curl -s -f "$NOMAD_ADDR/v1/nodes" 2>/dev/null); then
        return 1
    fi
    node_id=$(echo "$nodes" | jq -r --arg ip "$1" \
        '[.[]? | select(.Address == $ip and .Status == "ready") | .ID] | first // empty' 2>/dev/null || true)
    [ -z "$node_id" ] && return 0
    curl -s -f -X PUT --data '{"DrainSpec": {"Deadline": -1, "IgnoreSystemJobs": false}, "MarkEligible": false}' \
        "$NOMAD_ADDR/v1/node/$node_id/drain" >/dev/null || return 1
    NOMAD_DRAINED_NODE="$node_id"
}

# Ends the drain of nomad node $1 and makes it eligible again, so nomad starts the grid node there
# again and it registers with the hub
nomad_undrain_client() {
    curl -s -f -X PUT --data '{"DrainSpec": null, "MarkEligible": true}' "$NOMAD_ADDR/v1/node/$1/drain" >/dev/null
}

# Removes up to $1 nodes that have no session from the ARM pool, for a shrink while other nodes are
# running tests: a pool resize lets OCI pick the instances to terminate, which can be busy ones. Each
# node is first drained on the hub, so it takes no new session, and in nomad, so it is not started
# again, then its instance is detached from the pool, which terminates it and lowers the pool size by
# one. A node that got a session in between is left draining on the hub (it shuts down after the
# session, and nomad starts it again). Prints the number of nodes removed.
remove_idle_nodes() {
    local count="$1" idle instances removed=0
    idle=$(get_idle_grid_nodes)
    if ! instances=$(get_pool_instances "$NODE_POOL_ID_ARM"); then
        echo "Could not list the instances of pool $NODE_POOL_ID_ARM, not removing nodes" >&2
        echo 0
        return 0
    fi

    local id ip instance_id sessions
    while read -r id ip; do
        [ -z "$id" ] && continue
        [ "$removed" -ge "$count" ] && break
        instance_id=$(awk -v ip="$ip" '$1 == ip { print $2 }' <<< "$instances")
        if [ -z "$instance_id" ]; then
            continue
        fi
        if ! curl -s -f -X POST -H "X-REGISTRATION-SECRET;" "$GRID_URL/se/grid/distributor/node/$id/drain" >/dev/null; then
            echo "Could not drain node $id ($ip), leaving it" >&2
            continue
        fi
        # A session the distributor gave the node right before the drain
        sessions=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"query":"{ nodesInfo { nodes { id, sessionCount } } }"}' "$GRID_URL/graphql" 2>/dev/null \
            | jq -r --arg id "$id" '[.data.nodesInfo.nodes[]? | select(.id == $id) | .sessionCount] | first // 0' 2>/dev/null || echo 1)
        if [ "$sessions" != "0" ]; then
            echo "Node $id ($ip) got a session, leaving it draining" >&2
            continue
        fi
        echo "Removing idle node $id ($ip), instance $instance_id" >&2
        nomad_drain_client "$ip" || echo "Could not drain the nomad client $ip" >&2
        if oci compute-management instance-pool-instance detach --instance-pool-id "$NODE_POOL_ID_ARM" \
                --instance-id "$instance_id" --is-decrement-size true --is-auto-terminate true \
                --region "$ORACLE_REGION" >/dev/null; then
            removed=$((removed + 1))
        else
            # The node is out of the hub and stopped in nomad, but its instance stays in the pool: put it
            # back, and stop here, as the next detach would most likely fail the same way
            echo "Could not detach instance $instance_id from pool $NODE_POOL_ID_ARM, putting node $ip back" >&2
            if [ -n "$NOMAD_DRAINED_NODE" ] && ! nomad_undrain_client "$NOMAD_DRAINED_NODE"; then
                echo "Could not end the drain of nomad node $NOMAD_DRAINED_NODE ($ip)" >&2
            fi
            break
        fi
    done <<< "$idle"
    echo "$removed"
}

# A pool shrink terminates nodes without a consul leave, so consul keeps them as failed members
# (and their services in the catalog) for 72h, which fires Consul_Member_Failed. Removes the failed
# members of this grid, except those whose IP is still a running pool instance: an agent that stopped
# on a node that is up should still alert.
prune_failed_consul_members() {
    local failed
    failed=$(curl -s -f "$CONSUL_URL/v1/agent/members" 2>/dev/null \
        | jq -r --arg prefix "$ORACLE_REGION-$GRID_NAME-grid-" \
            '.[]? | select(.Status == 4 and (.Name | startswith($prefix))) | "\(.Name) \(.Addr)"' 2>/dev/null || true)
    [ -z "$failed" ] && return 0

    local running_ips
    if ! running_ips=$(get_pool_instance_ips "$NODE_POOL_ID_ARM" "$NODE_POOL_ID_X86"); then
        echo "Could not list the instances of the pools of grid $GRID_NAME, not pruning failed consul members"
        return 0
    fi

    local name addr
    while read -r name addr; do
        if echo "$running_ips" | grep -qxF "$addr"; then
            echo "Consul member $name ($addr) is failed but its instance is running, leaving it"
            continue
        fi
        echo "Pruning failed consul member $name ($addr), its instance is gone"
        curl -s -X PUT "$CONSUL_URL/v1/agent/force-leave/$name?prune=true" >/dev/null || true
    done <<< "$failed"
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

# Waits until the grid has the UP nodes for this build: its own slots on top of the sessions running
# and queued now, at most the desired pool size. The other reservations are not waited for: their
# builds wait for their own nodes, and a node of theirs that is still booting does not hold this one up.
wait_for_nodes() {
    local desired="$1"
    local timeout="$2"
    local own_slots="$3"
    local elapsed=0
    echo "Waiting for $own_slots free UP nodes on grid $GRID_URL, at most $desired (timeout: ${timeout}s)"
    while [ $elapsed -lt "$timeout" ]; do
        local up_count sessions queued needed
        up_count=$(get_grid_node_count)
        read -r sessions queued <<< "$(get_grid_sessions)"
        if [[ "$sessions" =~ ^[0-9]+$ ]] && [[ "$queued" =~ ^[0-9]+$ ]]; then
            needed=$((sessions + queued + own_slots))
            [ "$needed" -gt "$desired" ] && needed=$desired
        else
            needed=$desired
        fi
        echo "  UP nodes: $up_count / $needed (sessions: ${sessions:-?}, queued: ${queued:-?}, elapsed: ${elapsed}s)"
        if [ "$up_count" -ge "$needed" ] 2>/dev/null; then
            echo "Grid has $up_count UP nodes, ready"
            return 0
        fi
        sleep "$GRID_POLL_INTERVAL"
        elapsed=$((elapsed + GRID_POLL_INTERVAL))
    done
    echo "WARNING: Timed out waiting for ${needed:-$desired} UP nodes after ${timeout}s"
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
    # Like reconcile, leave alone a grid that is not managed: a grow here would never be undone
    if [ "$GRID_HAS_CONFIG" != "true" ]; then
        echo "No $CONSUL_KV_PREFIX/config in Consul, grid $GRID_NAME is not scaled, nothing to reserve"
        return 0
    fi

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

    # The minimum is a floor, not added to the reservations: the users of the grid reserve what they
    # use, and the warm nodes of the floor are there for the first of them
    local min_size max_size
    if [ "$arch" = "arm" ]; then
        min_size=$(get_scheduled_min_arm)
        max_size=$GRID_MAX_POOL_SIZE_ARM
    else
        min_size=$GRID_MIN_POOL_SIZE_X86
        max_size=$GRID_MAX_POOL_SIZE_X86
    fi
    local total_desired=$total_reserved
    if [ "$min_size" -gt "$total_desired" ]; then
        total_desired=$min_size
    fi
    if [ "$total_desired" -gt "$max_size" ]; then
        echo "Capping $total_desired at the maximum $max_size"
        total_desired=$max_size
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

    # Only grow here: shrinking terminates nodes that may be running sessions, it is left to scaledown
    local current_size
    current_size=$(get_pool_size "$pool_id")
    if [ "$current_size" -lt "$total_desired" ] 2>/dev/null; then
        resize_pool "$pool_id" "$total_desired"
    else
        echo "Pool size $current_size already covers the $total_desired needed, not resizing"
    fi

    # Wait for nodes to be UP. A scale-up takes ~12 minutes. When it takes longer, carry on with the
    # nodes there are: the tests then queue on the grid instead of not running at all.
    if ! wait_for_nodes "$total_desired" "$GRID_WAIT_TIMEOUT" "$GRID_SLOTS_REQUESTED"; then
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

# The ARM minimum for now: the min of the first config "schedule" window that covers the current UTC
# day of the week (1 is Monday) and time, e.g. {"days": "1-5", "from": "08:00", "to": "23:00",
# "min": 20}; min_pool_size_arm outside the windows and on the "holidays" (["2026-12-24", ...]).
get_scheduled_min_arm() {
    echo "$GRID_CONFIG_JSON" | jq -r --argjson day "$(date -u +%u)" --arg time "$(date -u +%H:%M)" \
        --arg date "$(date -u +%F)" --argjson base "$GRID_MIN_POOL_SIZE_ARM" '
        if ((.holidays // []) | index($date)) then $base
        else [(.schedule // [])[]
                | ((.days // "1-7") | split("-") | map(tonumber)) as $days
                | select($day >= $days[0] and $day <= ($days[1] // $days[0]))
                | select($time >= .from and $time < .to)
                | .min] | first // $base
        end' 2>/dev/null || echo "$GRID_MIN_POOL_SIZE_ARM"
}

# Reads an epoch from a Consul key under the grid prefix, empty when missing
get_kv_epoch() {
    local value
    value=$(curl -s -f "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/$1?raw" 2>/dev/null || echo "")
    [[ "$value" =~ ^[0-9]+$ ]] && echo "$value"
    return 0
}

# Sizes the ARM pool to what the grid needs: the reservations, at least the scheduled minimum, and at
# least the running and queued sessions (a user that made no reservation still gets nodes, one
# scale-up later) and the recent peak. Grows right away. Shrinks by at most GRID_SCALE_DOWN_STEP
# nodes per GRID_SCALE_DOWN_INTERVAL, after the cooldown since the last release and never with
# queued sessions: a grid idle for GRID_IDLE_SECONDS by resizing the pool, a grid running tests by
# removing nodes that have no session. Removes from consul the nodes an earlier shrink terminated.
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

    local now
    now=$(date +%s)

    # The peak sessions of the last GRID_PEAK_WINDOW seconds, so a grid that was just used keeps its
    # nodes for the next run
    local peak=0 peak_json peak_at=0
    peak_json=$(curl -s -f "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/recent_peak?raw" 2>/dev/null || echo "")
    if [ -n "$peak_json" ]; then
        peak=$(echo "$peak_json" | jq -r '.sessions // 0' 2>/dev/null || echo 0)
        peak_at=$(echo "$peak_json" | jq -r '.at // 0' 2>/dev/null || echo 0)
    fi
    if [ "$hub_known" = "true" ]; then
        if [ $((busy + queued)) -ge "$peak" ] || [ $((now - peak_at)) -ge "$GRID_PEAK_WINDOW" ]; then
            peak=$((busy + queued))
            curl -s -X PUT -d "{\"sessions\": $peak, \"at\": $now}" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/recent_peak" >/dev/null
        fi
        # How long the grid has been idle
        if [ "$busy" -eq 0 ] && [ "$queued" -eq 0 ]; then
            [ -z "$(get_kv_epoch idle_since)" ] && curl -s -X PUT -d "$now" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/idle_since" >/dev/null
        else
            curl -s -X DELETE "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/idle_since" >/dev/null
        fi
    fi

    local min_size
    min_size=$(get_scheduled_min_arm)
    local target=$reserved
    if [ "$min_size" -gt "$target" ]; then
        target=$min_size
    fi
    if [ $((busy + queued)) -gt "$target" ]; then
        target=$((busy + queued))
    fi
    if [ "$peak" -gt "$target" ]; then
        target=$peak
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

    # The nodes terminated by an earlier shrink (termination takes a minute or two after the resize)
    prune_failed_consul_members

    local pool current state
    pool=$(oci compute-management instance-pool get --instance-pool-id "$NODE_POOL_ID_ARM" --region "$ORACLE_REGION" 2>/dev/null \
        | jq -r '"\(.data.size) \(.data["lifecycle-state"])"' 2>/dev/null || true)
    read -r current state <<< "$pool"
    if ! [[ "$current" =~ ^[0-9]+$ ]]; then
        echo "Could not read the size of pool $NODE_POOL_ID_ARM"
        return 1
    fi
    echo "Pool $current ($state), target $target (min $min_size, reserved $reserved, sessions $busy, queued $queued, recent peak $peak)"

    if [ "$current" -lt "$target" ]; then
        resize_pool "$NODE_POOL_ID_ARM" "$target"
        # A shrink right after a grow would terminate the nodes still booting
        curl -s -X PUT -d "$now" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_resize_at" >/dev/null
        return 0
    fi
    if [ "$current" -eq "$target" ]; then
        return 0
    fi

    # OCI refuses to detach an instance from the pool while it is not RUNNING. A pool can stay out of
    # RUNNING for half an hour after a launch timed out on a slow instance, and each removal would
    # drain a node, retry the detach for minutes and put the node back
    if [ "$state" != "RUNNING" ]; then
        echo "Pool is $state, not shrinking"
        return 0
    fi
    if [ "$hub_known" != "true" ]; then
        echo "Could not read the sessions of $GRID_URL, not shrinking"
        return 0
    fi
    if [ "$queued" -ne 0 ]; then
        echo "Sessions queued, not shrinking"
        return 0
    fi
    if [ "$busy" -eq 0 ]; then
        local idle_since
        idle_since=$(get_kv_epoch idle_since)
        if [ -z "$idle_since" ] || [ $((now - idle_since)) -lt "$GRID_IDLE_SECONDS" ]; then
            echo "Idle for $((now - ${idle_since:-$now}))s of the ${GRID_IDLE_SECONDS}s needed, not shrinking"
            return 0
        fi
    fi
    local last_release
    last_release=$(get_kv_epoch last_release_at)
    if [ -n "$last_release" ] && [ $((now - last_release)) -lt "$GRID_COOLDOWN_SECONDS" ]; then
        echo "Cooldown active: $((now - last_release))s / ${GRID_COOLDOWN_SECONDS}s since last release, not shrinking"
        return 0
    fi
    local last_resize
    last_resize=$(get_kv_epoch last_resize_at)
    if [ -n "$last_resize" ] && [ $((now - last_resize)) -lt "$GRID_SCALE_DOWN_INTERVAL" ]; then
        echo "Resized $((now - last_resize))s ago, next step after ${GRID_SCALE_DOWN_INTERVAL}s"
        return 0
    fi

    # Step down, so a run that comes soon after still finds most of the nodes
    local step=$((current - target))
    if [ "$step" -gt "$GRID_SCALE_DOWN_STEP" ]; then
        step=$GRID_SCALE_DOWN_STEP
    fi
    if [ "$busy" -eq 0 ]; then
        # Nothing runs, so OCI can terminate any of the nodes
        resize_pool "$NODE_POOL_ID_ARM" $((current - step))
    else
        # A long run (a release validating shard after shard) would otherwise keep the pool at its
        # peak until it ends
        local removed
        removed=$(remove_idle_nodes "$step")
        echo "Removed $removed of $step idle nodes while $busy sessions run"
        [ "$removed" -eq 0 ] && return 0
    fi
    curl -s -X PUT -d "$now" "$CONSUL_URL/v1/kv/$CONSUL_KV_PREFIX/last_resize_at" >/dev/null
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

    local runs=0 repo status counts count old failed=false
    local since
    since=$(($(date +%s) - GRID_WATCH_MAX_AGE))
    for repo in $GRID_WATCH_REPOS; do
        for status in queued in_progress; do
            if ! counts=$(curl -s -f -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/$GRID_WATCH_OWNER/$repo/actions/workflows/$GRID_WATCH_WORKFLOW/runs?status=$status&per_page=100" \
                    | jq -er --argjson since "$since" \
                        '[.workflow_runs[] | (.created_at | fromdateiso8601) >= $since]
                         | "\(map(select(.)) | length) \(map(select(. | not)) | length)"'); then
                echo "Could not read the $status runs of $repo"
                failed=true
                continue
            fi
            read -r count old <<< "$counts"
            if [ "$old" -gt 0 ]; then
                echo "$repo: $count $status, not counting $old created more than ${GRID_WATCH_MAX_AGE}s ago"
            else
                echo "$repo: $count $status"
            fi
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
