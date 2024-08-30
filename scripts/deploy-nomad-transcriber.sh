#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="general"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$JIGASI_VERSION" ]; then
    [ -z "$JIGASI_TAG" ] && JIGASI_TAG="jigasi-$JIGASI_VERSION-1"
    export NOMAD_VAR_jigasi_version="$JIGASI_VERSION"
fi

[ -n "$JIGASI_RELEASE_NUMBER" ] && export NOMAD_VAR_release_number="$JIGASI_RELEASE_NUMBER"

[ -z "$JIGASI_TAG" ] && JIGASI_TAG="$DOCKER_TAG"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JIGASI_CREDENTIALS_FILE" ] && ENCRYPTED_JIGASI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jigasi.yml"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../ansible/secrets/asap-keys.yml"

JIGASI_XMPP_PASSWORD_VARIABLE="secrets_jigasi_brewery_by_environment_A.\"$ENVIRONMENT\""
JIGASI_SHARED_SECRET_VARIABLE="secrets_jigasi_conference_by_environment_A.\"$ENVIRONMENT\""
JIGASI_TRANSCRIBER_SECRET_VARIABLE="secrets_jigasi_transcriber_by_environment_A.\"$ENVIRONMENT\""

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_jigasi_xmpp_password="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_XMPP_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_jigasi_shared_secret="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_SHARED_SECRET_VARIABLE}" -)"
if [[ "$NOMAD_VAR_jigasi_shared_secret" == "null" ]]; then
    export NOMAD_VAR_jigasi_shared_secret=
fi

export NOMAD_VAR_jigasi_transcriber_password="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_TRANSCRIBER_SECRET_VARIABLE}" -)"
if [[ "$NOMAD_VAR_jigasi_transcriber_password" == "null" ]]; then
    export NOMAD_VAR_jigasi_transcriber_password=
fi

set -x

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"
export NOMAD_VAR_domain="$DOMAIN"
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_jigasi_tag="$JIGASI_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"

export NOMAD_JOB_NAME="transcriber-${ORACLE_REGION}"
export NOMAD_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-nomad.$TOP_LEVEL_DNS_ZONE_NAME"

sed -e "s/\[JOB_NAME\]/${NOMAD_JOB_NAME}/" "$NOMAD_JOB_PATH/transcriber.hcl" | nomad job run -var="dc=$NOMAD_DC" -
