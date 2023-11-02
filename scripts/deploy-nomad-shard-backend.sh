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

if [ -z "$SHARD" ]; then
    echo "No SHARD set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$SIGNAL_API_HOSTNAME" ] && SIGNAL_API_HOSTNAME="signal-api-$ENVIRONMENT.$TOP_LEVEL_DNS_ZONE_NAME"

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
    [ -z "$JICOFO_TAG" ] && JICOFO_TAG="jicofo-1.0-$JICOFO_VERSION-1"
fi

if [ -n "$JITSI_MEET_VERSION" ]; then
    [ -z "$WEB_TAG" ] && WEB_TAG="web-1.0.$JITSI_MEET_VERSION-1"
fi

if [ -n "$PROSODY_VERSION" ]; then
    [ -z "$PROSODY_TAG" ] && PROSODY_TAG="prosody-$PROSODY_VERSION"
fi


[ -z "$JICOFO_TAG" ] && JICOFO_TAG="$DOCKER_TAG"
[ -z "$WEB_TAG" ] && WEB_TAG="$DOCKER_TAG"
[ -z "$PROSODY_TAG" ] && PROSODY_TAG="$DOCKER_TAG"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENCRYPTED_JIBRI_CREDENTIALS_FILE" ] && ENCRYPTED_JIBRI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jibri.yml"
[ -z "$ENCRYPTED_JIGASI_CREDENTIALS_FILE" ] && ENCRYPTED_JIGASI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jigasi.yml"
[ -z "$ENCRYPTED_COTURN_CREDENTIALS_FILE" ] && ENCRYPTED_COTURN_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/coturn.yml"
[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../ansible/secrets/asap-keys.yml"
[ -z "$ENCRYPTED_PROSODY_EGRESS_AWS_FILE" ] && ENCRYPTED_PROSODY_EGRESS_AWS_FILE="$LOCAL_PATH/../ansible/secrets/prosody-egress-aws.yml"

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
BRANDING_NAME_VARIABLE="jitsi_meet_branding_override"
ASAP_KEY_VARIABLE="asap_key_$ENVIRONMENT_TYPE"

SIP_JIBRI_SHARED_SECRET_VARIABLE="sip_jibri_shared_secrets.\"$ENVIRONMENT\""

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

export NOMAD_VAR_asap_jwt_kid="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${ASAP_KEY_VARIABLE}.id" -)"

export NOMAD_VAR_aws_access_key_id="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_access_key_id_by_type.$ENVIRONMENT_TYPE" -)"
export NOMAD_VAR_aws_secret_access_key="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_secret_access_key_by_type.$ENVIRONMENT_TYPE" -)"

export NOMAD_VAR_jigasi_shared_secret="$NOMAD_VAR_jigasi_xmpp_password"

SIP_JIBRI_SHARED_SECRET="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIP_JIBRI_SHARED_SECRET_VARIABLE}" -)"
if [[ "$SIP_JIBRI_SHARED_SECRET" != "null" ]]; then
    export NOMAD_VAR_sip_jibri_shared_secret="$SIP_JIBRI_SHARED_SECRET"
fi

set -x

export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"

TURNRELAY_HOST_ARRAY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
if [[ "$TURNRELAY_HOST_ARRAY" == "null" ]]; then
    TURNRELAY_HOST_ARRAY="$(cat $MAIN_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
fi

if [[ "$TURNRELAY_HOST_ARRAY" != "null" ]]; then
    export NOMAD_VAR_turnrelay_host="$(echo $TURNRELAY_HOST_ARRAY | yq eval '.[0]' -)"
fi

export NOMAD_VAR_jwt_accepted_issuers="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_ISSUERS_VARIABLE} | @csv" -)"
export NOMAD_VAR_jwt_accepted_audiences="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_AUDIENCES_VARIABLE} | @csv" -)"

JWT_ACCEPTED_ISSUERS_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_ISSUERS_VARIABLE} | @csv" -)"
if [[ "$JWT_ACCEPTED_ISSUERS_ENV" != "null" ]]; then
    export NOMAD_VAR_jwt_accepted_issuers="$JWT_ACCEPTED_ISSUERS_ENV"
fi

JWT_ACCEPTED_AUDIENCES_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_AUDIENCES_VARIABLE} | @csv" -)"
if [[ "$JWT_ACCEPTED_AUDIENCES_ENV" != "null" ]]; then
    export NOMAD_VAR_jwt_accepted_audiences="$JWT_ACCEPTED_AUDIENCES_ENV"
fi

export ENABLE_MUC_ALLOWNERS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${ENABLE_MUC_ALLOWNERS_VARIABLE} -)"
if [[ "$ENABLE_MUC_ALLOWNERS" != "null" ]]; then
    export NOMAD_VAR_enable_muc_allowners="$ENABLE_MUC_ALLOWNERS"
fi

PROSODY_MUC_MODERATED_ROOMS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".prosody_muc_moderated_rooms | @csv" -)"
if [ -n "$PROSODY_MUC_MODERATED_ROOMS" ]; then
    if [[ "$PROSODY_MUC_MODERATED_ROOMS" != "null" ]]; then
        export NOMAD_VAR_muc_moderated_rooms="$PROSODY_MUC_MODERATED_ROOMS"
    fi
fi


PROSODY_MUC_MODERATED_SUBDOMAINS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".prosody_muc_moderated_subdomains | @csv" -)"
if [ -n "$PROSODY_MUC_MODERATED_SUBDOMAINS" ]; then
    if [[ "$PROSODY_MUC_MODERATED_SUBDOMAINS" != "null" ]]; then
        export NOMAD_VAR_muc_moderated_subdomains="$PROSODY_MUC_MODERATED_SUBDOMAINS"
    fi
fi

export FILTER_IQ_RAYO_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_enable_filter_iq_rayo -)"
if [[ "$FILTER_IQ_RAYO_ENABLED" != "null" ]]; then
    export NOMAD_VAR_filter_iq_rayo_enabled="$FILTER_IQ_RAYO_ENABLED"
fi

# check main configuration file for rate limit whitelist
export PROSODY_RATE_LIMIT_ALLOW_RANGES="$(cat $MAIN_CONFIGURATION_FILE | yq eval '.prosody_rate_limit_whitelist| @csv' -)"
if [ -n "$PROSODY_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$PROSODY_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export NOMAD_VAR_prosody_rate_limit_allow_ranges="$PROSODY_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

# check environment configuration file for rate limit whitelist
export PROSODY_RATE_LIMIT_ALLOW_RANGES="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.prosody_rate_limit_whitelist | @csv' -)"
if [ -n "$PROSODY_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$PROSODY_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export NOMAD_VAR_prosody_rate_limit_allow_ranges="$PROSODY_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

export WEBHOOKS_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_meet_webhooks_enabled -)"
if [[ "$WEBHOOKS_ENABLED" != "null" ]]; then
    export NOMAD_VAR_webhooks_enabled="$WEBHOOKS_ENABLED"
fi

export SCTP_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jicofo_enable_sctp -)"
if [[ "$SCTP_ENABLED" != "null" ]]; then
    export NOMAD_VAR_sctp_enabled="$SCTP_ENABLED"
fi

export SCTP_RELAY_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jicofo_enable_sctp_relay -)"
if [[ "$SCTP_RELAY_ENABLED" != "null" ]]; then
    export NOMAD_VAR_sctp_relay_enabled="$SCTP_RELAY_ENABLED"
fi

export PROSODY_EGRESS_FALLBACK_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_egress_fallback_url -)"
if [[ "$PROSODY_EGRESS_FALLBACK_URL" != "null" ]]; then
    export NOMAD_VAR_prosody_egress_fallback_url="$PROSODY_EGRESS_FALLBACK_URL"
fi

export MUC_EVENTS_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_enable_muc_events -)"
if [[ "$MUC_EVENTS_ENABLED" != "null" ]]; then
    export NOMAD_VAR_muc_events_enabled="$MUC_EVENTS_ENABLED"
fi

BRANDING_NAME="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${BRANDING_NAME_VARIABLE} -)"
if [[ "$BRANDING_NAME" != "null" ]]; then
    export NOMAD_VAR_web_repo="$AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME"
    WEB_TAG="$JITSI_MEET_VERSION"
else
    BRANDING_NAME="jitsi-meet"
fi

VISITORS_COUNT_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .visitors_count -)"
if [[ "$VISITORS_COUNT_ENV" != "null" ]]; then
    VISITORS_COUNT=$VISITORS_COUNT_ENV
fi

VISITORS_ENABLED_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .visitors_enabled -)"
if [[ "$VISITORS_ENABLED_ENV" != "null" ]]; then
    VISITORS_ENABLED=$VISITORS_ENABLED_ENV
fi

WAIT_FOR_HOSTS_ENABLED_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_enable_wait_for_host -)"
if [[ "$WAIT_FOR_HOSTS_ENABLED_ENV" != "null" ]]; then
    WAIT_FOR_HOSTS_ENABLED=$WAIT_FOR_HOSTS_ENABLED_ENV
fi

JWT_ALLOW_EMPTY_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_token_allow_empty -)"
if [[ "$JWT_ALLOW_EMPTY_ENV" != "null" ]]; then
    JWT_ALLOW_EMPTY=$JWT_ALLOW_EMPTY_ENV
fi

PASSWORD_WAITING_FOR_HOST_ENABLED_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_enable_password_waiting_for_host -)"
if [[ "$PASSWORD_WAITING_FOR_HOST_ENABLED_ENV" != "null" ]]; then
    PASSWORD_WAITING_FOR_HOST_ENABLED=$PASSWORD_WAITING_FOR_HOST_ENABLED_ENV
fi

ASAP_DISABLE_REQUIRE_ROOM_CLAIM_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_disable_required_room_claim -)"
if [[ "$ASAP_DISABLE_REQUIRE_ROOM_CLAIM_ENV" != "null" ]]; then
    ASAP_DISABLE_REQUIRE_ROOM_CLAIM=$ASAP_DISABLE_REQUIRE_ROOM_CLAIM_ENV
fi

PROSODY_CACHE_KEYS_URL_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_cache_keys_url -)"
if [[ "$PROSODY_CACHE_KEYS_URL_ENV" != "null" ]]; then
    PROSODY_CACHE_KEYS_URL=$PROSODY_CACHE_KEYS_URL_ENV
fi

AMPLITUDE_API_KEY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_amplitude_api_key -)"
if [[ "$AMPLITUDE_API_KEY" != "null" ]]; then
    export NOMAD_VAR_amplitude_api_key="$AMPLITUDE_API_KEY"
fi

RTCSTATS_SERVER="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jicofo_rtcstats_push_rtcstats_server -)"
if [[ "$RTCSTATS_SERVER" != "null" ]]; then
    export NOMAD_VAR_rtcstats_server="$RTCSTATS_SERVER"
fi



[ -z "$VISITORS_COUNT" ] && VISITORS_COUNT=0

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_shard="$SHARD"
export NOMAD_VAR_shard_id="$(echo $SHARD| rev | cut -d"-" -f1 | rev | tr -d '[:alpha:]')"
export NOMAD_VAR_octo_region="$ORACLE_REGION"
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_release_number="$RELEASE_NUMBER"
export NOMAD_VAR_signal_version="$SIGNAL_VERSION"
export NOMAD_VAR_jicofo_tag="$JICOFO_TAG"
export NOMAD_VAR_prosody_tag="$PROSODY_TAG"
export NOMAD_VAR_web_tag="$WEB_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"
export NOMAD_VAR_branding_name="$BRANDING_NAME"
export NOMAD_VAR_visitors_count="$VISITORS_COUNT"
export NOMAD_VAR_visitors_enabled="$VISITORS_ENABLED"
export NOMAD_VAR_wait_for_host_enabled="$WAIT_FOR_HOSTS_ENABLED"
export NOMAD_VAR_jwt_allow_empty="$JWT_ALLOW_EMPTY"
export NOMAD_VAR_asap_disable_require_room_claim="$ASAP_DISABLE_REQUIRE_ROOM_CLAIM"
export NOMAD_VAR_password_waiting_for_host_enabled="$PASSWORD_WAITING_FOR_HOST_ENABLED"
export NOMAD_VAR_prosody_cache_keys_url="$PROSODY_CACHE_KEYS_URL"
export NOMAD_VAR_signal_api_domain_name="$SIGNAL_API_HOSTNAME"

sed -e "s/\[JOB_NAME\]/shard-${SHARD}/" "$NOMAD_JOB_PATH/jitsi-meet-backend.hcl" | nomad job run -var="dc=$NOMAD_DC" -
exit $?
