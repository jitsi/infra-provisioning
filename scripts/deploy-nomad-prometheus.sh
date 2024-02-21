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

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-prometheus"

[ -z "$PROMETHEUS_ENABLE_REMOTE_WRITE" ] && PROMETHEUS_ENABLE_REMOTE_WRITE="false"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_prometheus_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_dc="$NOMAD_DC"

if [[ "$PROMETHEUS_ENABLE_REMOTE_WRITE" == "true" ]]; then
  export NOMAD_VAR_enable_remote_write="true"
  if [[ "$ENVIRONMENT_TYPE" = "prod" ]]; then
    PROMETHEUS_ENVIRONMENT_TYPE="prod"
  else
    PROMETHEUS_ENVIRONMENT_TYPE="non_prod"
  fi

  [ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"
  [ -z "$ENCRYPTED_PROMETHEUS_FILE" ] && ENCRYPTED_PROMETHEUS_FILE="$LOCAL_PATH/../ansible/secrets/prometheus.yml"

  # ensure no output for ansible vault contents and fail if ansible-vault fails
  set +x
  set -e
  set -o pipefail
  export NOMAD_VAR_remote_write_url="$(ansible-vault view $ENCRYPTED_PROMETHEUS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prometheus_endpoints_by_type.$PROMETHEUS_ENVIRONMENT_TYPE" -)"
  export NOMAD_VAR_remote_write_username="$(ansible-vault view $ENCRYPTED_PROMETHEUS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prometheus_credentials_by_type.$PROMETHEUS_ENVIRONMENT_TYPE.username" -)"
  export NOMAD_VAR_remote_write_password="$(ansible-vault view $ENCRYPTED_PROMETHEUS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prometheus_credentials_by_type.$PROMETHEUS_ENVIRONMENT_TYPE.password" -)"
  export NOMAD_VAR_remote_write_org_id="$(ansible-vault view $ENCRYPTED_PROMETHEUS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prometheus_credentials_by_type.$PROMETHEUS_ENVIRONMENT_TYPE.username" -)"
  set -x
fi

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