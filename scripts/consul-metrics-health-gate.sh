#!/bin/bash
# consul-metrics-health-gate.sh -- Mimir/Loki-aware health gate for consul-node rotations.
#
# The consul pool carries one mimir-N ingester (RF=3) and one loki-N instance
# (RF=1) per node. Rotating a node moves its allocs to the replacement node, which
# has to attach the volume, replay the WAL and rejoin the ring before the NEXT
# node may be touched. This script is what rotate-consul-oracle.sh waits on
# instead of a blind sleep (doc/mimir-cluster-plan.md section 5a).
#
#   consul-metrics-health-gate.sh pre    one-shot: exit non-zero if the clusters are not
#                                        fully healthy (never start a rotation against an
#                                        already-degraded cluster)
#   consul-metrics-health-gate.sh post   poll until healthy or HEALTH_GATE_TIMEOUT_MINUTES
#                                        elapses (default 15); exit non-zero on timeout
#
# A job that is not deployed in the region is skipped (the very first rotation, the
# one that attaches the mimir volumes, happens before mimir exists). A nomad API
# failure is NOT treated as "not deployed": the gate fails closed.
#
# Env: ENVIRONMENT, ORACLE_REGION (required); HEALTH_GATE_TIMEOUT_MINUTES,
#      HEALTH_GATE_POLL_SECONDS, HEALTH_GATE_REQUIRE_LOKI (default true),
#      MIMIR_HOSTNAME, LOKI_HOSTNAME, NOMAD_ADDR (all optional).

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "## health-gate: ERROR no ENVIRONMENT set"
  exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$ORACLE_REGION" ]; then
  echo "## health-gate: ERROR no ORACLE_REGION set"
  exit 2
fi

MODE="${1:-post}"
if [[ "$MODE" != "pre" && "$MODE" != "post" ]]; then
  echo "## health-gate: ERROR unknown mode '$MODE' (expected pre|post)"
  exit 2
fi

[ -z "$HEALTH_GATE_TIMEOUT_MINUTES" ] && HEALTH_GATE_TIMEOUT_MINUTES=15
[ -z "$HEALTH_GATE_POLL_SECONDS" ] && HEALTH_GATE_POLL_SECONDS=20
[ -z "$HEALTH_GATE_REQUIRE_LOKI" ] && HEALTH_GATE_REQUIRE_LOKI="true"
[ -z "$HEALTH_GATE_EXPECTED_REPLICAS" ] && HEALTH_GATE_EXPECTED_REPLICAS=3

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"
if [ -z "$NOMAD_ADDR" ]; then
  export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$MIMIR_HOSTNAME" ] && MIMIR_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-mimir.$TOP_LEVEL_DNS_ZONE_NAME"
[ -z "$LOKI_HOSTNAME" ] && LOKI_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-loki.$TOP_LEVEL_DNS_ZONE_NAME"
MIMIR_JOB="mimir-$ORACLE_REGION"
LOKI_JOB="loki-$ORACLE_REGION"

log() { echo "## health-gate[$MODE]: $*"; }

# prints present | missing | error
job_state() {
  local out
  out=$(nomad job status -short "$1" 2>&1)
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    echo present
  elif echo "$out" | grep -qi 'No job(s) with prefix or ID'; then
    echo missing
  else
    log "nomad job status $1 failed: $out"
    echo error
  fi
}

# running (desired=run, client=running) allocation count for a job
running_allocs() {
  nomad job allocs -json "$1" 2>/dev/null | jq -r '[.[] | select(.DesiredStatus=="run" and .ClientStatus=="running")] | length' 2>/dev/null
}

# dskit ring status page as JSON -> "active not_active total"
ring_summary() {
  curl -sf -m 10 -H 'Accept: application/json' "$1" 2>/dev/null \
    | jq -r '[.shards[]?] | "\(map(select(.state=="ACTIVE"))|length) \(map(select(.state!="ACTIVE"))|length) \(length)"' 2>/dev/null
}

# N consecutive 200s through the LB so more than one backend is sampled
ready_ok() {
  local url="$1" i code
  for i in 1 2 3; do
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)
    [[ "$code" == "200" ]] || { log "$url -> $code"; return 1; }
  done
  return 0
}

# check_cluster <name> <job> <hostname> <ready path> <ring path> -> 0 healthy, 1 not
check_cluster() {
  local name="$1" job="$2" host="$3" ready_path="$4" ring_path="$5"
  local allocs summary active other total

  allocs=$(running_allocs "$job")
  if [[ -z "$allocs" || "$allocs" -lt "$HEALTH_GATE_EXPECTED_REPLICAS" ]]; then
    log "$name: ${allocs:-?}/$HEALTH_GATE_EXPECTED_REPLICAS allocs running"
    return 1
  fi

  if ! ready_ok "https://$host$ready_path"; then
    log "$name: $ready_path not 200"
    return 1
  fi

  summary=$(ring_summary "https://$host$ring_path")
  if [[ -z "$summary" ]]; then
    log "$name: could not read ring at $ring_path"
    return 1
  fi
  read -r active other total <<< "$summary"
  if [[ "$active" -ne "$HEALTH_GATE_EXPECTED_REPLICAS" || "$other" -ne 0 ]]; then
    log "$name: ring $active ACTIVE / $other not-active / $total total (want $HEALTH_GATE_EXPECTED_REPLICAS/0)"
    return 1
  fi
  log "$name: $allocs allocs running, $ready_path 200, ring $active/$total ACTIVE"
  return 0
}

# one full pass over everything we gate on -> 0 healthy, 1 not healthy, 2 fatal
check_all() {
  local healthy=0 state

  state=$(job_state "$MIMIR_JOB")
  case "$state" in
    present)
      check_cluster mimir "$MIMIR_JOB" "$MIMIR_HOSTNAME" /ready /ingester/ring || healthy=1
      ;;
    missing)
      log "mimir: job $MIMIR_JOB not deployed in this region, skipping"
      ;;
    *) return 2 ;;
  esac

  if [[ "$HEALTH_GATE_REQUIRE_LOKI" == "true" ]]; then
    state=$(job_state "$LOKI_JOB")
    case "$state" in
      present)
        check_cluster loki "$LOKI_JOB" "$LOKI_HOSTNAME" /ready /ring || healthy=1
        ;;
      missing)
        log "loki: job $LOKI_JOB not deployed in this region, skipping"
        ;;
      *) return 2 ;;
    esac
  fi
  return $healthy
}

if [[ "$MODE" == "pre" ]]; then
  check_all
  RET=$?
  if [[ $RET -eq 0 ]]; then
    log "clusters healthy, rotation may proceed"
  else
    log "REFUSING to rotate: metrics/logs cluster is not fully healthy (set HEALTH_GATE=false to override)"
  fi
  exit $RET
fi

# post: poll until healthy or timeout
DEADLINE=$(( $(date +%s) + HEALTH_GATE_TIMEOUT_MINUTES * 60 ))
log "waiting up to ${HEALTH_GATE_TIMEOUT_MINUTES}m for mimir/loki to be fully healthy in $ORACLE_REGION"
while true; do
  check_all
  RET=$?
  if [[ $RET -eq 0 ]]; then
    log "clusters healthy after wait"
    exit 0
  fi
  if [[ $RET -eq 2 ]]; then
    log "nomad API unavailable; failing closed"
    exit 2
  fi
  if [[ $(date +%s) -ge $DEADLINE ]]; then
    log "TIMEOUT after ${HEALTH_GATE_TIMEOUT_MINUTES}m; not rolling on to the next pool"
    exit 1
  fi
  sleep "$HEALTH_GATE_POLL_SECONDS"
done
