#!/bin/bash
# Pattern from deploy-nomad-loki.sh (includes CNAME creation)

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$ALLOY_HOSTNAME" ] && ALLOY_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-otel.$TOP_LEVEL_DNS_ZONE_NAME"
[ -z "$ALLOY_LOKI_HOSTNAME" ] && ALLOY_LOKI_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-otel-loki.$TOP_LEVEL_DNS_ZONE_NAME"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_alloy_hostname="${ALLOY_HOSTNAME}"
export NOMAD_VAR_alloy_loki_hostname="${ALLOY_LOKI_HOSTNAME}"
JOB_NAME="alloy-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"
if [[ "$ENVIRONMENT_TYPE" = "prod" ]]; then
    export NOMAD_VAR_environment_type="prod"
else
    export NOMAD_VAR_environment_type="nonprod"
fi

# ---- metrics pipeline (doc/mimir-cluster-plan.md Phase 2); override per env in stack-env.sh ----
# write metrics to the regional mimir-cluster (deploy it first: scripts/deploy-nomad-mimir.sh)
[ -z "$ALLOY_ENABLE_MIMIR_WRITE" ] && ALLOY_ENABLE_MIMIR_WRITE="false"
export NOMAD_VAR_enable_mimir_write="$ALLOY_ENABLE_MIMIR_WRITE"
# keep relaying OTLP metrics to the legacy regional prometheus (off at cutover)
[ -z "$ALLOY_ENABLE_LEGACY_PROMETHEUS_WRITE" ] && ALLOY_ENABLE_LEGACY_PROMETHEUS_WRITE="true"
export NOMAD_VAR_enable_legacy_prometheus_write="$ALLOY_ENABLE_LEGACY_PROMETHEUS_WRITE"
# take over the consul-SD scrape jobs from prometheus.hcl
[ -z "$ALLOY_ENABLE_SCRAPE" ] && ALLOY_ENABLE_SCRAPE="false"
export NOMAD_VAR_enable_scrape="$ALLOY_ENABLE_SCRAPE"
# primary | ha | none -- how scraped streams reach the external 8x8 Mimir (see alloy.hcl)
[ -z "$ALLOY_EXTERNAL_SCRAPE_FORWARD" ] && ALLOY_EXTERNAL_SCRAPE_FORWARD="primary"
export NOMAD_VAR_external_scrape_forward="$ALLOY_EXTERNAL_SCRAPE_FORWARD"

# alloy-syntax equivalents of prometheus_custom_relabels / prometheus_custom_external_labels
ALLOY_CUSTOM_RELABEL_RULES=$(cat $MAIN_CONFIGURATION_FILE | yq eval ".alloy_custom_relabel_rules")
if [[ "$ALLOY_CUSTOM_RELABEL_RULES" != "null" ]]; then
    export NOMAD_VAR_custom_relabel_rules="$ALLOY_CUSTOM_RELABEL_RULES"
fi
ALLOY_CUSTOM_EXTERNAL_LABELS=$(cat $MAIN_CONFIGURATION_FILE | yq eval ".alloy_custom_external_labels")
if [[ "$ALLOY_CUSTOM_EXTERNAL_LABELS" != "null" ]]; then
    export NOMAD_VAR_custom_external_labels="$ALLOY_CUSTOM_EXTERNAL_LABELS"
fi

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/alloy.hcl" | nomad job run -var="dc=$NOMAD_DC" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad alloy job, exiting"
    exit 5
fi

# Create CNAME pointing to internal load balancer (same pattern as loki)
export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-otel"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

# Create CNAME for Loki push API endpoint (used by Vector routing through Alloy)
export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-otel-loki"
export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
