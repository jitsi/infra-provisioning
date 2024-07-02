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

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="dev"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-alertmanager"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="alertmanager-$ORACLE_REGION"
export NOMAD_VAR_alertmanager_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"

if [ -z "$DEFAULT_ALERT_SERVICE_NAME" ]; then
    export NOMAD_VAR_default_service_name=$DEFAULT_ALERT_SERVICE_NAME
else
    export NOMAD_VAR_default_service_name="default"
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"
[ -z "$ENCRYPTED_NOMAD_SECRETS_FILE" ] && ENCRYPTED_NOMAD_SECRETS_FILE="$LOCAL_PATH/../ansible/secrets/nomad.yml"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_slack_api_url="$(ansible-vault view $ENCRYPTED_NOMAD_SECRETS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".nomad_slack_api_url" -)"
export NOMAD_VAR_pagerduty_urls_by_service="$(ansible-vault view $ENCRYPTED_NOMAD_SECRETS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".nomad_pagerduty_urls_by_service" -)"
set -x

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/alertmanager.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh

exit $RET