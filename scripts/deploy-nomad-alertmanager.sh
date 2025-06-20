#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ "$ENVIRONMENT_TYPE" == "prod" ]; then
    ALERT_SLACK_CHANNEL=$ENVIRONMENT
else
    ALERT_SLACK_CHANNEL="dev"
fi

[ -z "$ALERTMANAGER_PAGES_ENABLED" ] && ALERTMANAGER_PAGES_ENABLED="false"

[ -z "$GLOBAL_ALERTMANAGER" ] && GLOBAL_ALERTMANAGER="false"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

if [ -z "$EMAIL_ALERT_URL" ]; then
    export EMAIL_ALERT_URL="https://$ENVIRONMENT-$ORACLE_REGION-alert-emailer.$TOP_LEVEL_DNS_ZONE_NAME/alerts"
fi

if [ "$GLOBAL_ALERTMANAGER" == "true" ]; then
    SERVICE_NAME="alertmanager-global"
else
    SERVICE_NAME="alertmanager"
fi
export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-${SERVICE_NAME}"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="$SERVICE_NAME-$ORACLE_REGION"
export NOMAD_VAR_email_alert_url=$EMAIL_ALERT_URL
export NOMAD_VAR_alertmanager_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_slack_channel_suffix="${ALERT_SLACK_CHANNEL}"
export NOMAD_VAR_pagerduty_enabled="${ALERTMANAGER_PAGES_ENABLED}"
export NOMAD_VAR_global_alertmanager="${GLOBAL_ALERTMANAGER}"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/alertmanager.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $RET