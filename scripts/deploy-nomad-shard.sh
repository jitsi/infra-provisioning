#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

if [ -z "$SHARD" ]; then
    echo "No SHARD set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$ORACLE_REGION"

if [ -z "$NOMAD_ADDR" ]; then
    NOMAD_IPS="$(DATACENTER="$ENVIRONMENT-$LOCAL_REGION" OCI_DATACENTERS="$ENVIRONMENT-$LOCAL_REGION" ENVIRONMENT="$ENVIRONMENT" FILTER_ENVIRONMENT="false" SHARD='' RELEASE_NUMBER='' SERVICE="nomad-servers" DISPLAY="addresses" $LOCAL_PATH/consul-search.sh ubuntu)"
    if [ -n "$NOMAD_IPS" ]; then
        NOMAD_IP="$(echo $NOMAD_IPS | cut -d ' ' -f1)"
        export NOMAD_ADDR="http://$NOMAD_IP:4646"
    else
        echo "No NOMAD_IPS for in environment $ENVIRONMENT in consul"
        exit 5
    fi
fi

if [ -z "$NOMAD_ADDR" ]; then
    echo "Failed to set NOMAD_ADDR, exiting"
    exit 5
fi

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="general"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$SIGNAL_VERSION" ]; then
    if [ -z "$JICOFO_VERSION" ]; then
        JICOFO_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f1)"
    fi
    if [ -z "$JITSI_MEET_VERSION" ]; then
        JITSI_MEET_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f2)"
    fi
    if [ -z "$PROSODY_VERSION" ]; then
        PROSODY_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f3)"
    fi
else
    if [ -n "$JICOFO_VERSION" ]; then
        SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
    else
        SIGNAL_VERSION="$DOCKER_TAG"
    fi
fi

if [ -n "$JICOFO_VERSION" ]; then
    JICOFO_TAG="jicofo-1.0-$JICOFO_VERSION-1"
fi

if [ -n "$JITSI_MEET_VERSION" ]; then
    WEB_TAG="web-1.0.$JITSI_MEET_VERSION-1"
fi

if [ -n "$PROSODY_VERSION" ]; then
    PROSODY_TAG="prosody-$PROSODY_VERSION"
fi

[ -z "$JICOFO_TAG" ] && JICOFO_TAG="$DOCKER_TAG"
[ -z "$WEB_TAG" ] && WEB_TAG="$DOCKER_TAG"
[ -z "$PROSODY_TAG" ] && PROSODY_TAG="$DOCKER_TAG"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENCRYPTED_JIBRI_CREDENTIALS_FILE" ] && ENCRYPTED_JIBRI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jibri.yml"
[ -z "$ENCRYPTED_JIGASI_CREDENTIALS_FILE" ] && ENCRYPTED_JIGASI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jigasi.yml"
[ -z "$ENCRYPTED_COTURN_CREDENTIALS_FILE" ] && ENCRYPTED_COTURN_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/coturn.yml"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

JVB_XMPP_PASSWORD_VARIABLE="jvb_xmpp_password"
JIBRI_XMPP_PASSWORD_VARIABLE="jibri_auth_password"
JIBRI_RECORDER_PASSWORD_VARIABLE="jibri_selenium_auth_password"
JIGASI_XMPP_PASSWORD_VARIABLE="jigasi_xmpp_password"
JICOFO_XMPP_PASSWORD_VARIABLE="prosody_focus_user_secret"

JWT_ASAP_KEYSERVER_VARIABLE="prosody_public_key_repo_url"
JWT_ACCEPTED_ISSUERS_VARIABLE="prosody_asap_accepted_issuers"
JWT_ACCEPTED_AUDIENCES_VARIABLE="prosody_asap_accepted_audiences"
TURNRELAY_HOST_VARIABLE="prosody_mod_turncredentials_hosts"
TURNRELAY_PASSWORD_VARIABLE="coturn_secret"
ENABLE_MUC_ALLOWNERS_VARIABLE="prosody_muc_allowners"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_jvb_auth_password="$(ansible-vault view $ENCRYPTED_JVB_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JVB_XMPP_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_jibri_xmpp_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_XMPP_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_jibri_recorder_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_RECORDER_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_jigasi_xmpp_password="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_XMPP_PASSWORD_VARIABLE}" -)"
export NOMAD_VAR_turnrelay_password="$(ansible-vault view $ENCRYPTED_COTURN_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${TURNRELAY_PASSWORD_VARIABLE}" -)"

export NOMAD_VAR_jicofo_auth_password="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${JICOFO_XMPP_PASSWORD_VARIABLE} -)"
export NOMAD_VAR_jwt_asap_keyserver="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${JWT_ASAP_KEYSERVER_VARIABLE} -)"
set -x

TURNRELAY_HOST_ARRAY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
if [[ "$TURNRELAY_HOST_ARRAY" == "null" ]]; then
    TURNRELAY_HOST_ARRAY="$(cat $MAIN_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
fi

if [[ "$TURNRELAY_HOST_ARRAY" != "null" ]]; then
    export NOMAD_VAR_turnrelay_host="$(echo $TURNRELAY_HOST_ARRAY | yq eval '.[0]' -)"
fi

export NOMAD_VAR_jwt_accepted_issuers="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_ISSUERS_VARIABLE} | @csv" -)"
export NOMAD_VAR_jwt_accepted_audiences="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_AUDIENCES_VARIABLE} | @csv" -)"
export ENABLE_MUC_ALLOWNERS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${ENABLE_MUC_ALLOWNERS_VARIABLE} -)"
if [[ "$ENABLE_MUC_ALLOWNERS" != "null" ]]; then
    export NOMAD_VAR_enable_muc_allowners="$ENABLE_MUC_ALLOWNERS"
fi

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_shard="$SHARD"
export NOMAD_VAR_octo_region="$ORACLE_REGION"
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_release_number="$RELEASE_NUMBER"
export NOMAD_VAR_signal_version="$SIGNAL_VERSION"
export NOMAD_VAR_jicofo_tag="$JICOFO_TAG"
export NOMAD_VAR_web_tag="$WEB_TAG"
export NOMAD_VAR_prosody_tag="$PROSODY_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"

sed -e "s/\[JOB_NAME\]/$SHARD/" "$NOMAD_JOB_PATH/shard.hcl" | nomad job run -var="dc=$NOMAD_DC" -
