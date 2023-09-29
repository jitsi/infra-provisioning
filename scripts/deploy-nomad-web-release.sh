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
BRANDING_NAME_VARIABLE="jitsi_meet_branding_override"

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


TOKEN_AUTH_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_token_auth_url -)"
TOKEN_LOGOUT_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_token_logout_url -)"
TOKEN_AUTH_AUTO_REDIRECT="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_token_auth_url_auto_redirect -)"
TOKEN_SSO="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_token_sso -)"

if [[ "$TOKEN_AUTH_URL" != "null" ]]; then
    export NOMAD_VAR_token_auth_url="$TOKEN_AUTH_URL"
fi
if [[ "$TOKEN_LOGOUT_URL" != "null" ]]; then
    export NOMAD_VAR_token_logout_url="$TOKEN_LOGOUT_URL"
fi
if [[ "$TOKEN_AUTH_AUTO_REDIRECT" != "null" ]]; then
    export NOMAD_VAR_token_auth_auto_redirect="$TOKEN_AUTH_AUTO_REDIRECT"
fi
if [[ "$TOKEN_SSO" != "null" ]]; then
    export NOMAD_VAR_token_sso="$TOKEN_SSO"
fi

INSECURE_ROOM_NAME_WARNING="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_unsafe_room_warning -)"
if [[ "$INSECURE_ROOM_NAME_WARNING" != "null" ]]; then
    export NOMAD_VAR_insecure_room_name_warning="$INSECURE_ROOM_NAME_WARNING"
fi

JVB_PREFER_SCTP="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_prefer_sctp -)"
if [[ "$JVB_PREFER_SCTP" != "null" ]]; then
    export NOMAD_VAR_jvb_prefer_sctp="$JVB_PREFER_SCTP"
fi

AMPLITUDE_API_KEY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_amplitude_api_key -)"
AMPLITUDE_INCLUDE_UTM="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_amplitude_include_utm -)"
if [[ "$AMPLITUDE_API_KEY" != "null" ]]; then
    export NOMAD_VAR_amplitude_api_key="$AMPLITUDE_API_KEY"
fi
if [[ "$AMPLITUDE_INCLUDE_UTM" != "null" ]]; then
    export NOMAD_VAR_amplitude_include_utm="$AMPLITUDE_INCLUDE_UTM"
fi


RTCSTATS_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_enabled -)"
RTCSTATS_STORE_LOGS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_store_logs -)"
RTCSTATS_USE_LEGACY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_use_legacy -)"
RTCSTATS_ENDPOINT="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_endpoint -)"
RTCSTATS_POLL_INTERVAL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_poll_interval -)"
RTCSTATS_LOG_SDP="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_rtcstats_log_sdp -)"
if [[ "$RTCSTATS_ENABLED" != "null" ]]; then
    export NOMAD_VAR_rtcstats_enabled="$RTCSTATS_ENABLED"
fi
if [[ "$RTCSTATS_STORE_LOGS" != "null" ]]; then
    export NOMAD_VAR_rtcstats_store_logs="$RTCSTATS_STORE_LOGS"
fi
if [[ "$RTCSTATS_USE_LEGACY" != "null" ]]; then
    export NOMAD_VAR_rtcstats_use_legacy="$RTCSTATS_USE_LEGACY"
fi
if [[ "$RTCSTATS_ENDPOINT" != "null" ]]; then
    export NOMAD_VAR_rtcstats_endpoint="$RTCSTATS_ENDPOINT"
fi
if [[ "$RTCSTATS_POLL_INTERVAL" != "null" ]]; then
    export NOMAD_VAR_rtcstats_poll_interval="$RTCSTATS_POLL_INTERVAL"
fi
if [[ "$RTCSTATS_LOG_SDP" != "null" ]]; then
    export NOMAD_VAR_rtcstats_log_sdp="$RTCSTATS_LOG_SDP"
fi

ANALYTICS_WHITELIST="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_analytics_whitelist -)"
if [[ "$ANALYTICS_WHITELIST" != "null" ]]; then
    export NOMAD_VAR_analytics_white_listed_events="$ANALYTICS_WHITELIST"
fi

VIDEO_RESOLUTION="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_resolution -)"
if [[ "$VIDEO_RESOLUTION" != "null" ]]; then
    export NOMAD_VAR_video_resolution="$VIDEO_RESOLUTION"
fi

CONFERENCE_REQUEST_HTTP_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_conference_request_http -)"
if [[ "$CONFERENCE_REQUEST_HTTP_ENABLED" != "null" ]]; then
    export NOMAD_VAR_conference_request_http_enabled="$CONFERENCE_REQUEST_HTTP_ENABLED"
fi


GOOGLE_API_APP_CLIENT_ID="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_google_api_app_client_id -)"
if [[ "$GOOGLE_API_APP_CLIENT_ID" != "null" ]]; then
    export NOMAD_VAR_google_api_app_client_id="$GOOGLE_API_APP_CLIENT_ID"
fi

MICROSOFT_API_APP_CLIENT_ID="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_microsoft_api_app_client_id -)"
if [[ "$MICROSOFT_API_APP_CLIENT_ID" != "null" ]]; then
    export NOMAD_VAR_microsoft_api_app_client_id="$MICROSOFT_API_APP_CLIENT_ID"
fi

CALENDAR_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_calendar -)"
if [[ "$CALENDAR_ENABLED" != "null" ]]; then
    export NOMAD_VAR_calendar_enabled="$CALENDAR_ENABLED"
fi

DROPBOX_APP_KEY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_dropbox_app_key -)"
if [[ "$DROPBOX_APP_KEY" != "null" ]]; then
    export NOMAD_VAR_dropbox_appkey="$DROPBOX_APP_KEY"
fi


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

BRANDING_NAME="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${BRANDING_NAME_VARIABLE} -)"
if [[ "$BRANDING_NAME" != "null" ]]; then
    export NOMAD_VAR_web_repo="$AWS_ECR_REPO_HOST/jitsi/$BRANDING_NAME"
    WEB_TAG="$JITSI_MEET_VERSION"
else
    BRANDING_NAME="jitsi-meet"
fi

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_octo_region="$ORACLE_REGION"
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_release_number="$RELEASE_NUMBER"
export NOMAD_VAR_signal_version="$SIGNAL_VERSION"
export NOMAD_VAR_jicofo_tag="$JICOFO_TAG"
export NOMAD_VAR_web_tag="$WEB_TAG"
export NOMAD_VAR_prosody_tag="$PROSODY_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"
export NOMAD_VAR_branding_name="$BRANDING_NAME"

sed -e "s/\[JOB_NAME\]/release-${RELEASE_NUMBER}/" "$NOMAD_JOB_PATH/jitsi-meet-web.hcl" | nomad job run -var="dc=$NOMAD_DC" -
