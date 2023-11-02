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

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="JVB"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$JVB_VERSION" ]; then
    JVB_TAG="jvb-$JVB_VERSION-1"
    export NOMAD_VAR_jvb_version="$JVB_VERSION"
fi

[ -z "$JVB_TAG" ] && JVB_TAG="$DOCKER_TAG"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../ansible/secrets/asap-keys.yml"

ASAP_KEY_VARIABLE="asap_key_$ENVIRONMENT_TYPE"

JVB_XMPP_PASSWORD_VARIABLE="jvb_xmpp_password"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_jvb_auth_password="$(ansible-vault view $ENCRYPTED_JVB_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JVB_XMPP_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_asap_jwt_kid="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${ASAP_KEY_VARIABLE}.id" -)"

set -x

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"
export NOMAD_VAR_domain="$DOMAIN"
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_jvb_tag="$JVB_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"
export NOMAD_VAR_release_number="$RELEASE_NUMBER"
export NOMAD_VAR_shard="$SHARD"

[ -z "$JVB_POOL_TYPE" ] && export NOMAD_VAR_jvb_pool_type="$JVB_POOL_TYPE"

export NOMAD_JOB_NAME="jvb-release-${RELEASE_NUMBER}-${ORACLE_REGION}"
export NOMAD_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-nomad.$TOP_LEVEL_DNS_ZONE_NAME"

sed -e "s/\[JOB_NAME\]/${NOMAD_JOB_NAME}/" "$NOMAD_JOB_PATH/jvb.hcl" | nomad job run -var="dc=$NOMAD_DC" -
exit $?
