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

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-prometheus"

[ -z "$PROMETHEUS_ENABLE_REMOTE_WRITE" ] && PROMETHEUS_ENABLE_REMOTE_WRITE="false"

# the environment has a core deployment (shards, jvbs, etc)
[ -z "$CLOUDPROBER_TEMPLATE_TYPE" ] && CLOUDPROBER_TEMPLATE_TYPE="base"
if [ "$CLOUDPROBER_TEMPLATE_TYPE" == "core" ]; then
    export NOMAD_VAR_core_deployment="true"
fi

# the environment offers extended services (jibri, jicofo, etc)
[ -z "$PROMETHEUS_CORE_EXTENDED_SERVICES" ] && PROMETHEUS_CORE_EXTENDED_SERVICES="false"
if [ "$PROMETHEUS_CORE_EXTENDED_SERVICES" == "true" ]; then
    export NOMAD_VAR_core_extended_services="true"
fi

# apply more aggressive production alert thresholds to the environment
[ -z "$PROMETHEUS_PRODUCTION_ALERTS" ] && PROMETHEUS_PRODUCTION_ALERTS="false"
if [ "$PROMETHEUS_PRODUCTION_ALERTS" == "true" ]; then
    export NOMAD_VAR_production_alerts="true"
fi

# autoscaler is deployed in this environment
[ -z "$PROMETHEUS_AUTOSCALER_ALERTS" ] && PROMETHEUS_AUTOSCALER_ALERTS="false"
if [ "$PROMETHEUS_AUTOSCALER_ALERTS" == "true" ]; then
    export NOMAD_VAR_autoscaler_alerts="true"
fi

PROMETHEUS_CUSTOM_ALERTS=$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".prometheus_custom_alerts")
if [[ "$PROMETHEUS_CUSTOM_ALERTS" != "null" ]]; then
    export NOMAD_VAR_custom_alerts="$PROMETHEUS_CUSTOM_ALERTS"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_prometheus_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_dc="$NOMAD_DC"

if [[ "$PROMETHEUS_ENABLE_REMOTE_WRITE" == "true" ]]; then
    export NOMAD_VAR_enable_remote_write="true"
fi

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="dev"
if [[ "$ENVIRONMENT_TYPE" = "prod" ]]; then
    export NOMAD_VAR_environment_type="prod"
else
    export NOMAD_VAR_environment_type="nonprod"
fi

[ -z "$GRAFANA_ALERTS_DASHBOARD_URL" ] && GRAFANA_ALERTS_DASHBOARD_URL=""
export NOMAD_VAR_grafana_url="$GRAFANA_ALERTS_DASHBOARD_URL"

[ -z "$GLOBAL_ALERTMANAGER_HOST" ] && GLOBAL_ALERTMANAGER_HOST=""
export NOMAD_VAR_global_alertmanager_host="$GLOBAL_ALERTMANAGER_HOST"

JOB_NAME="prometheus-$ORACLE_REGION"
sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/prometheus.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $RET