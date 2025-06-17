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

if [ -z "$COMPARTMENT_OCID" ]; then
    echo "No COMPARTMENT_OCID set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ ! -z "$ALERT_EMAILER_IMAGE_TAG" ]; then
    export NOMAD_VAR_image_tag="$ALERT_EMAILER_IMAGE_TAG"
fi

if [ ! -z "$DOCKER_IMAGE_HOST" ]; then
    export NOMAD_VAR_docker_image_host="$DOCKER_IMAGE_HOST"
else
    export NOMAD_VAR_docker_image_host="ops-prod-us-phoenix-1-registry.jitsi.net"
fi

if [ ! -z "$NOTIFICATION_EMAIL" ]; then
    export NOMAD_VAR_notification_email="$NOTIFICATION_EMAIL"
    export NOMAD_VAR_check_notification_email="true"
else
    export NOMAD_VAR_check_notification_email="false"
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-alert-emailer"

export NOMAD_VAR_compartment_ocid=$COMPARTMENT_OCID
export NOMAD_VAR_topic_name="$ENVIRONMENT-topic"
export NOMAD_VAR_region="$ORACLE_REGION"
export NOMAD_VAR_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"

if [ ! -z "$DEFAULT_SERVICE_LOG_LEVEL" ]; then
    export NOMAD_VAR_log_level="$DEFAULT_SERVICE_LOG_LEVEL"
else
    export NOMAD_VAR_log_level="WARN"
fi

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="alert-emailer-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/alert-emailer.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $RET