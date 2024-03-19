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

[ -z "$ENCRYPTED_OCI_CREDENTIALS_FILE" ] && ENCRYPTED_OCI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/oci-certificates.yml"
OCI_API_USER_VARIABLE="oci_api_user"
OCI_API_PASSPHRASE_VARIABLE="oci_api_pass_phrase"
OCI_API_KEY_FINGERPRINT_VARIABLE="oci_api_key_fingerprint"
OCI_API_TENANCY_VARIABLE="oci_api_tenancy"
OCI_API_REGION_VARIABLE="oci_api_region"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_oci_user="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_USER_VARIABLE}" -)"
export NOMAD_VAR_oci_passphrase="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_PASSPHRASE_VARIABLE}" -)"
export NOMAD_VAR_oci_fingerprint="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_KEY_FINGERPRINT_VARIABLE}" -)"
export NOMAD_VAR_oci_tenancy="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_TENANCY_VARIABLE}" -)"
export NOMAD_VAR_oci_key_region="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_REGION_VARIABLE}" -)"

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

set +x

cat > "./autoscaler.hcl" <<EOF
datacenters=["$NOMAD_DC"]
hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
version="$AUTOSCALER_VERSION"
$ASAP_BASE_URL_CONFIG
redis_from_consul=$REDIS_FROM_CONSUL
redis_host="$REDIS_HOST"
redis_tls=$REDIS_TLS
EOF

set -x
set +e

JOB_NAME="autoscaler-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./autoscaler.hcl" \
  $PACKS_DIR/jitsi_autoscaler

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning nomad autoscaler job, exiting"
    rm ./autoscaler.hcl
    exit 4
else
    if [ $PLAN_RET -eq 1 ]; then
        echo "Plan was successful, will make changes"
    fi
    if [ $PLAN_RET -eq 0 ]; then
        echo "Plan was successful, no changes needed"
    fi
fi

nomad-pack run --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./autoscaler.hcl" \
  $PACKS_DIR/jitsi_autoscaler

if [ $? -ne 0 ]; then
    echo "Failed to run nomad autoscaler job, exiting"
    rm ./autoscaler.hcl
    exit 5
fi

rm ./autoscaler.hcl

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
