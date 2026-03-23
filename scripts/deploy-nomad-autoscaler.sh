#!/bin/bash

set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

if [ -z "$ASAP_BASE_URL" ]; then
    if [ -n "$ASAP_PUBLIC_KEY_URL" ]; then 
        ASAP_BASE_URL="$ASAP_PUBLIC_KEY_URL/server/$ENVIRONMENT_TYPE"
    fi
fi
if [ -n "$ASAP_BASE_URL" ]; then
    ASAP_BASE_URL_CONFIG="asap_base_url=\"$ASAP_BASE_URL\""
fi

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

set -x

REDIS_FROM_CONSUL="true"
REDIS_TLS="false"
REDIS_HOST="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_redis_host_by_region.$ORACLE_REGION" -)"
if [[ "$REDIS_HOST" == "null" ]]; then
    REDIS_HOST="localhost"
else
    # redis host set, so do not use consul
    REDIS_FROM_CONSUL="false"
    REDIS_TLS="true"
fi

METRICS_PROVIDER="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_metrics_provider" -)"
if [[ "$METRICS_PROVIDER" == "null" ]]; then
    METRICS_PROVIDER=""
fi

ENABLE_PROMETHEUS="false"
if [[ "$METRICS_PROVIDER" == "prometheus" ]]; then
    ENABLE_PROMETHEUS="true"
fi

CLOUD_GUARD_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_cloud_guard_enabled" -)"
if [[ "$CLOUD_GUARD_ENABLED" == "null" ]]; then
    CLOUD_GUARD_ENABLED="false"
fi

CLOUD_GUARD_GRACE_COUNT="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_cloud_guard_grace_count" -)"
if [[ "$CLOUD_GUARD_GRACE_COUNT" == "null" ]]; then
    CLOUD_GUARD_GRACE_COUNT="0"
fi

SCHEDULED_SCALING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_scheduled_scaling_enabled" -)"
if [[ "$SCHEDULED_SCALING_ENABLED" == "null" ]]; then
    SCHEDULED_SCALING_ENABLED="true"
fi

SCHEDULED_SCALING_DEFAULT_TIMEZONE="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_scheduled_scaling_default_timezone" -)"
if [[ "$SCHEDULED_SCALING_DEFAULT_TIMEZONE" == "null" ]]; then
    SCHEDULED_SCALING_DEFAULT_TIMEZONE="UTC"
fi

AUTOSCALER_LOG_LEVEL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_log_level" -)"
if [[ "$AUTOSCALER_LOG_LEVEL" == "null" ]]; then
    AUTOSCALER_LOG_LEVEL="info"
fi

AUTOSCALER_NODE_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_node_env" -)"
if [[ "$AUTOSCALER_NODE_ENV" == "null" ]]; then
    AUTOSCALER_NODE_ENV="production"
fi

[ -z "$JOBS_CONCURRENCY" ] && JOBS_CONCURRENCY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".autoscaler_jobs_concurrency" -)"
if [[ "$JOBS_CONCURRENCY" == "null" ]] || [[ -z "$JOBS_CONCURRENCY" ]]; then
    JOBS_CONCURRENCY="5"
fi

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
# for ORACLE_REGION in $REGIONS; do
#     NOMAD_DC="$( echo "$NOMAD_DC" "[\"$ENVIRONMENT-$ORACLE_REGION\"]" | jq -c -s '.|add')"
# done

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$AUTOSCALER_VERSION" ] && AUTOSCALER_VERSION="latest"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-autoscaler"

cat > "./autoscaler.hcl" <<EOF
datacenters=["$NOMAD_DC"]
hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
version="$AUTOSCALER_VERSION"
$ASAP_BASE_URL_CONFIG
redis_from_consul=$REDIS_FROM_CONSUL
redis_host="$REDIS_HOST"
redis_tls=$REDIS_TLS
enable_prometheus=$ENABLE_PROMETHEUS
prometheus_url="https://$ENVIRONMENT-$ORACLE_REGION-prometheus.$TOP_LEVEL_DNS_ZONE_NAME"
oci_compartment_id="$COMPARTMENT_OCID"
cloud_guard_enabled=$CLOUD_GUARD_ENABLED
cloud_guard_grace_count=$CLOUD_GUARD_GRACE_COUNT
scheduled_scaling_enabled=$SCHEDULED_SCALING_ENABLED
scheduled_scaling_default_timezone="$SCHEDULED_SCALING_DEFAULT_TIMEZONE"
log_level="$AUTOSCALER_LOG_LEVEL"
node_env="$AUTOSCALER_NODE_ENV"
jobs_concurrency=$JOBS_CONCURRENCY
EOF

JOB_NAME="autoscaler-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

nomad-pack plan --deploy-override --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./autoscaler.hcl" \
  $PACKS_DIR/jitsi_autoscaler

PLAN_RET=$?

echo "PLAN_RET=$PLAN_RET"
# nomad-pack plan --deploy-override is broken in v0.4.2 (hashicorp/nomad-pack#845)
# treat plan error (255) as non-fatal since run --deploy-override works correctly
if [ $PLAN_RET -gt 1 ]; then
    echo "Plan returned error, will attempt run with --deploy-override"
elif [ $PLAN_RET -eq 1 ]; then
    echo "Plan was successful, will make changes"
elif [ $PLAN_RET -eq 0 ]; then
    echo "Plan was successful, no changes needed"
fi

nomad-pack run --deploy-override --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./autoscaler.hcl" \
  $PACKS_DIR/jitsi_autoscaler

if [ $? -ne 0 ]; then
    echo "Failed to run nomad autoscaler job, exiting"
    rm ./autoscaler.hcl
    exit 5
fi

rm ./autoscaler.hcl

scripts/nomad-pack.sh status jitsi_autoscaler --name "$JOB_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to get status for autoscaler job, exiting"
    exit 6
fi
nomad-watch --out "deploy" started "$JOB_NAME"
WATCH_RET=$?
if [ $WATCH_RET -ne 0 ]; then
    echo "Failed starting job, dumping logs and exiting"
    nomad-watch started "$JOB_NAME"
fi

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $WATCH_RET