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

[ -z "$ENCRYPTED_WAVEFRONT_CREDENTIALS_FILE" ] && ENCRYPTED_WAVEFRONT_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/wavefront.yml"
[ -z "$ENCRYPTED_OCI_CREDENTIALS_FILE" ] && ENCRYPTED_OCI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/oci-certificates.yml"
OCI_API_USER_VARIABLE="oci_api_user"
OCI_API_PASSPHRASE_VARIABLE="oci_api_pass_phrase"
OCI_API_KEY_FINGERPRINT_VARIABLE="oci_api_key_fingerprint"
OCI_API_TENANCY_VARIABLE="oci_api_tenancy"
OCI_API_REGION_VARIABLE="oci_api_region"


WAVEFRONT_TOKEN_VARIABLE="wavefront_api_token"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_wavefront_token="$(ansible-vault view $ENCRYPTED_WAVEFRONT_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${WAVEFRONT_TOKEN_VARIABLE}" -)"
export NOMAD_VAR_oci_user="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_USER_VARIABLE}" -)"
export NOMAD_VAR_oci_passphrase="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_PASSPHRASE_VARIABLE}" -)"
export NOMAD_VAR_oci_fingerprint="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_KEY_FINGERPRINT_VARIABLE}" -)"
export NOMAD_VAR_oci_tenancy="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_TENANCY_VARIABLE}" -)"
export NOMAD_VAR_oci_key_region="$(ansible-vault view $ENCRYPTED_OCI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${OCI_API_REGION_VARIABLE}" -)"

set -x

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
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

export NOMAD_VAR_dc="$NOMAD_DC"
export NOMAD_VAR_autoscaler_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_autoscaler_version="${AUTOSCALER_VERSION}"
export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"

JOB_NAME="autoscaler-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/autoscaler.hcl" | nomad job run -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad autoscaler job, exiting"
    exit 5
fi

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
