#!/bin/bash
#
# Show OCI compute capacity for a role's default shape across every region in
# an environment, per availability domain and fault domain.
#
#   ENVIRONMENT=prod-8x8 scripts/check-capacity-oracle.sh consul
#   ENVIRONMENT=prod-8x8 ORACLE_REGION=sa-saopaulo-1 scripts/check-capacity-oracle.sh shard
#   ENVIRONMENT=prod-8x8 scripts/check-capacity-oracle.sh shard --watch 300
#
# The role picks SHAPE, OCPUS and MEMORY_IN_GBS exactly as the matching
# create/rotate script would, from the site's stack-env.sh and clouds/oracle.sh.
# Any of SHAPE, OCPUS or MEMORY_IN_GBS set in the environment overrides the
# role default, so a hypothetical shape can be checked without a role:
#
#   ENVIRONMENT=prod-8x8 SHAPE=VM.Standard.E5.Flex OCPUS=4 MEMORY_IN_GBS=16 scripts/check-capacity-oracle.sh
#
# Options:
#   --watch SECONDS   repeat until interrupted, printing a timestamp each pass
#   --json            raw per-fault-domain json instead of the compact table
#   --full            one line per fault domain instead of one per AD

for arg in "$@"; do
  if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]; then
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
  fi
done

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "## ERROR: check-capacity-oracle must have ENVIRONMENT set; exiting..."
  exit 2
fi

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

ROLE=""
WATCH=""
OUTPUT_ARGS=(--compact)
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH="$2"; shift 2 ;;
    --json) OUTPUT_ARGS=(--json); shift ;;
    --full) OUTPUT_ARGS=(); shift ;;
    *) ROLE="$1"; shift ;;
  esac
done

# resolve the role's default shape and size the way its create/rotate script does;
# explicit SHAPE/OCPUS/MEMORY_IN_GBS from the caller always win
case "$ROLE" in
  consul)
    # terraform/consul-server/create-consul-server-oracle.sh
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_CONSUL_SHAPE"
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS=4
    else
      [ -z "$OCPUS" ] && OCPUS=2
    fi
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    ;;
  shard|signal|core)
    # terraform/shard-core/create-shard-core-oracle.sh (VISITORS_FACTOR not applied)
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_SIGNAL_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="$SIGNAL_MEMORY_IN_GBS"
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS="$SIGNAL_OCPUS"
      [ -z "$OCPUS" ] && OCPUS=8
    elif [[ "$SHAPE" == "$SHAPE_A_2" ]]; then
      [ -z "$OCPUS" ] && [ -n "$SIGNAL_OCPUS" ] && OCPUS="$((SIGNAL_OCPUS/2))"
      [ -z "$OCPUS" ] && OCPUS=4
    else
      [ -z "$OCPUS" ] && OCPUS="$SIGNAL_OCPUS"
      [ -z "$OCPUS" ] && OCPUS=4
    fi
    ;;
  haproxy)
    # terraform/haproxy-shards/create-haproxy-stack-oracle.sh
    [ -z "$SHAPE" ] && SHAPE="$HAPROXY_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_HAPROXY_SHAPE"
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS=4
    else
      [ -z "$OCPUS" ] && OCPUS=2
    fi
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    ;;
  nomad-pool|nomad)
    # terraform/nomad-pool/create-nomad-pool-stack.sh
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_NOMAD_POOL_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS=12
    else
      [ -z "$OCPUS" ] && OCPUS=6
    fi
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=64
    ;;
  coturn)
    # terraform/create-coturn-stack/create-coturn-stack-oracle.sh
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_COTURN_SHAPE"
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS=8
    else
      [ -z "$OCPUS" ] && OCPUS=4
    fi
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    ;;
  jvb)
    # scripts/create-or-rotate-custom-jvb-oracle.sh
    [ -z "$SHAPE" ] && SHAPE="$JVB_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_SHAPE"
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$OCPUS" ] && OCPUS=8
    else
      [ -z "$OCPUS" ] && OCPUS=4
    fi
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
    ;;
  jibri)
    # scripts/create-or-rotate-jibri-oracle.sh (java-jibri)
    [ -z "$SHAPE" ] && SHAPE="$JIBRI_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_JIBRI_SHAPE"
    case "$SHAPE" in
      "$SHAPE_E_3") [ -z "$OCPUS" ] && OCPUS=4; [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16 ;;
      "$SHAPE_E_6") [ -z "$OCPUS" ] && OCPUS=1; [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8 ;;
      "$SHAPE_A_1") [ -z "$OCPUS" ] && OCPUS=4; [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8 ;;
      *) [ -z "$OCPUS" ] && OCPUS=2; [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8 ;;
    esac
    ;;
  sip-jibri)
    # scripts/create-or-rotate-jibri-oracle.sh (sip-jibri)
    [ -z "$SHAPE" ] && SHAPE="$SIP_JIBRI_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_SIP_JIBRI_SHAPE"
    [ -z "$OCPUS" ] && OCPUS=8
    if [[ "$SHAPE" == "$SHAPE_A_1" ]]; then
      [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8
    else
      [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    fi
    ;;
  "")
    if [ -z "$SHAPE" ]; then
      echo "## ERROR: give a role (consul, shard, haproxy, nomad-pool, coturn, jvb, jibri, sip-jibri) or set SHAPE; exiting..."
      exit 2
    fi
    ;;
  *)
    echo "## ERROR: unknown role '$ROLE'; known roles: consul, shard, haproxy, nomad-pool, coturn, jvb, jibri, sip-jibri"
    exit 2
    ;;
esac

if [ -z "$SHAPE" ]; then
  echo "## ERROR: no default shape resolved for role '$ROLE' in $ENVIRONMENT; set SHAPE explicitly"
  exit 2
fi

SHAPE_CONFIG_ARGS=()
[ -n "$OCPUS" ] && SHAPE_CONFIG_ARGS+=(--ocpus "$OCPUS")
[ -n "$MEMORY_IN_GBS" ] && SHAPE_CONFIG_ARGS+=(--memory-in-gbs "$MEMORY_IN_GBS")

REGION_ARGS=()
for r in $ORACLE_REGION $ORACLE_REGIONS_OVERRIDE; do
  REGION_ARGS+=(--region "$r")
done

# oci_capacity.py resolves the environment's regions from sites/$ENVIRONMENT/stack-env.sh
# relative to the working directory, so run it from the repo root
cd "$LOCAL_PATH/.." || exit 1

run_once() {
  echo "# $ENVIRONMENT ${ROLE:-shape} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  "$LOCAL_PATH/oci_capacity.py" --environment "$ENVIRONMENT" list_compute_capacity \
    "${REGION_ARGS[@]}" --shape "$SHAPE" "${SHAPE_CONFIG_ARGS[@]}" "${OUTPUT_ARGS[@]}"
}

if [ -z "$WATCH" ]; then
  run_once
  exit $?
fi

while true; do
  run_once
  echo
  sleep "$WATCH"
done
