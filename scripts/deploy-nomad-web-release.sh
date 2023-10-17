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

CHANNEL_LAST_N="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_channel_last_n -)"
if [[ "$CHANNEL_LAST_N" != "null" ]]; then
    export NOMAD_VAR_channel_last_n="$CHANNEL_LAST_N"
fi

SSRC_REWRITING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_ssrc_rewriting -)"
if [[ "$SSRC_REWRITING_ENABLED" != "null" ]]; then
    export NOMAD_VAR_ssrc_rewriting_enabled="$SSRC_REWRITING_ENABLED"
fi

RESTRICT_HD_TILE_VIEW_JVB="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_restrict_HD_tile_view_jvb -)"
if [[ "$RESTRICT_HD_TILE_VIEW_JVB" != "null" ]]; then
    export NOMAD_VAR_restrict_hd_tile_view_jvb="$RESTRICT_HD_TILE_VIEW_JVB"
fi


DTX_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_dtx -)"
if [[ "$DTX_ENABLED" != "null" ]]; then
    export NOMAD_VAR_dtx_enabled="$DTX_ENABLED"
fi

HIDDEN_FROM_RECORDER_FEATURE="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_hidden_from_recorder_feature -)"
if [[ "$HIDDEN_FROM_RECORDER_FEATURE" != "null" ]]; then
    export NOMAD_VAR_hidden_from_recorder_feature="$HIDDEN_FROM_RECORDER_FEATURE"
fi

TRANSCRIPTIONS_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_transcription -)"
if [[ "$TRANSCRIPTIONS_ENABLED" != "null" ]]; then
    export NOMAD_VAR_transcriptions_enabled="$TRANSCRIPTIONS_ENABLED"
fi

LIVESTREAMING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_livestreaming -)"
if [[ "$LIVESTREAMING_ENABLED" != "null" ]]; then
    export NOMAD_VAR_livestreaming_enabled="$LIVESTREAMING_ENABLED"
fi

SERVICE_RECORDING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_file_recordings -)"
if [[ "$SERVICE_RECORDING_ENABLED" != "null" ]]; then
    export NOMAD_VAR_service_recording_enabled="$SERVICE_RECORDING_ENABLED"
fi

SERVICE_RECORDING_SHARING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_file_recordings_sharing -)"
if [[ "$SERVICE_RECORDING_SHARING_ENABLED" != "null" ]]; then
    export NOMAD_VAR_service_recording_sharing_enabled="$SERVICE_RECORDING_SHARING_ENABLED"
fi

LOCAL_RECORDING_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_local_recording -)"
if [[ "$LOCAL_RECORDING_ENABLED" == "false" ]]; then
    export NOMAD_VAR_local_recording_disabled="true"
fi

API_DIALIN_NUMBERS_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_dialin_numbers_url -)"
if [[ "$API_DIALIN_NUMBERS_URL" != "null" ]]; then
    export NOMAD_VAR_api_dialin_numbers_url="$API_DIALIN_NUMBERS_URL"
fi

API_CONFERENCE_MAPPER_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_conference_mapper_url -)"
if [[ "$API_CONFERENCE_MAPPER_URL" != "null" ]]; then
    export NOMAD_VAR_api_conference_mapper_url="$API_CONFERENCE_MAPPER_URL"
fi

API_DIALOUT_AUTH_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_dialout_auth_url -)"
if [[ "$API_DIALOUT_AUTH_URL" != "null" ]]; then
    export NOMAD_VAR_api_dialout_auth_url="$API_DIALOUT_AUTH_URL"
fi

API_DIALOUT_CODES_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_dialout_codes_url -)"
if [[ "$API_DIALOUT_CODES_URL" != "null" ]]; then
    export NOMAD_VAR_api_dialout_codes_url="$API_DIALOUT_CODES_URL"
fi

API_DIALOUT_REGION_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_dialout_region_url -)"
if [[ "$API_DIALOUT_REGION_URL" != "null" ]]; then
    export NOMAD_VAR_api_dialout_region_url="$API_DIALOUT_REGION_URL"
fi

API_RECORDING_SHARING_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_recoding_sharing_url -)"
if [[ "$API_RECORDING_SHARING_URL" != "null" ]]; then
    export NOMAD_VAR_api_recoding_sharing_url="$API_RECORDING_SHARING_URL"
fi

GUEST_DIAL_OUT_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_guest_dial_out_url -)"
if [[ "$GUEST_DIAL_OUT_URL" != "null" ]]; then
    export NOMAD_VAR_api_guest_dial_out_url="$GUEST_DIAL_OUT_URL"
fi

GUEST_DIAL_OUT_STATUS_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_guest_dial_out_status_url -)"
if [[ "$GUEST_DIAL_OUT_STATUS_URL" != "null" ]]; then
    export NOMAD_VAR_api_guest_dial_out_status_url="$GUEST_DIAL_OUT_STATUS_URL"
fi

REQUIRE_DISPLAY_NAME="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_require_displayname -)"
if [[ "$REQUIRE_DISPLAY_NAME" != "null" ]]; then
    export NOMAD_VAR_require_display_name="$REQUIRE_DISPLAY_NAME"
fi

START_VIDEO_MUTED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_start_video_muted_count -)"
if [[ "$START_VIDEO_MUTED" != "null" ]]; then
    export NOMAD_VAR_start_video_muted="$START_VIDEO_MUTED"
fi

START_AUDIO_MUTED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_start_audio_muted_count -)"
if [[ "$START_AUDIO_MUTED" != "null" ]]; then
    export NOMAD_VAR_start_audio_muted="$START_AUDIO_MUTED"
fi

USER_ROLE_BASED_ON_TOKEN_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_user_roles_based_on_token -)"
if [[ "$USER_ROLE_BASED_ON_TOKEN_ENABLED" != "null" ]]; then
    export NOMAD_VAR_token_based_roles_enabled="$USER_ROLE_BASED_ON_TOKEN_ENABLED"
fi

PERFORMANCE_STATS_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_performance_stats -)"
if [[ "$PERFORMANCE_STATS_ENABLED" != "null" ]]; then
    export NOMAD_VAR_performance_stats_enabled="$PERFORMANCE_STATS_ENABLED"
fi

PREJOIN_PAGE_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_enable_prejoin_page -)"
if [[ "$PREJOIN_PAGE_ENABLED" != "null" ]]; then
    export NOMAD_VAR_prejoin_page_enabled="$PREJOIN_PAGE_ENABLED"
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

JAAS_ACTUATOR_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .prosody_jaas_actuator_url -)"
if [[ "$JAAS_ACTUATOR_URL" != "null" ]]; then
    export NOMAD_VAR_jaas_actuator_url="$JAAS_ACTUATOR_URL"
fi

JAAS_TOKEN_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_jaas_token_url -)"
if [[ "$JAAS_TOKEN_URL" != "null" ]]; then
    export NOMAD_VAR_api_jaas_token_url="$JAAS_TOKEN_URL"
fi

JAAS_WEBHOOK_PROXY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_jaas_webhook_proxy -)"
if [[ "$JAAS_WEBHOOK_PROXY" != "null" ]]; then
    export NOMAD_VAR_api_jaas_webhook_proxy="$JAAS_WEBHOOK_PROXY"
fi

API_BILLING_COUNTER="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_billing_counter -)"
if [[ "$API_BILLING_COUNTER" != "null" ]]; then
    export NOMAD_VAR_api_billing_counter="$API_BILLING_COUNTER"
fi

API_BRANDING_DATA_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_branding_data_url -)"
if [[ "$API_BRANDING_DATA_URL" != "null" ]]; then
    export NOMAD_VAR_api_branding_data_url="$API_BRANDING_DATA_URL"
fi



API_DIRECTORY_SEARCH_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_directory_search_url -)"
if [[ "$API_DIRECTORY_SEARCH_URL" != "null" ]]; then
    export NOMAD_VAR_api_directory_search_url="$API_DIRECTORY_SEARCH_URL"
fi

API_CONFERENCE_INVITE_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_conference_invite_url -)"
if [[ "$API_CONFERENCE_INVITE_URL" != "null" ]]; then
    export NOMAD_VAR_api_conference_invite_url="$API_CONFERENCE_INVITE_URL"
fi

# callflows are deprecated ?
API_CONFERENCE_INVITE_CALLFLOWS_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_api_conference_invite_callflows_url -)"
if [[ "$API_CONFERENCE_INVITE_CALLFLOWS_URL" != "null" ]]; then
    export NOMAD_VAR_api_conference_invite_callflows_url="$API_CONFERENCE_INVITE_CALLFLOWS_URL"
fi

WHITEBOARD_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_whiteboard_enabled -)"
if [[ "$WHITEBOARD_ENABLED" != "null" ]]; then
    export NOMAD_VAR_whiteboard_enabled="$WHITEBOARD_ENABLED"
fi

WHITEBOARD_SERVER_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_whiteboard_collab_server_base_url -)"
if [[ "$WHITEBOARD_SERVER_URL" != "null" ]]; then
    export NOMAD_VAR_whiteboard_server_url="$WHITEBOARD_SERVER_URL"
fi

GIPHY_ENABLED="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_giphy_enabled -)"
if [[ "$GIPHY_ENABLED" != "null" ]]; then
    export NOMAD_VAR_giphy_enabled="$GIPHY_ENABLED"
fi

GIPHY_SDK_KEY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .jitsi_meet_giphy_sdk_key -)"
if [[ "$GIPHY_SDK_KEY" != "null" ]]; then
    export NOMAD_VAR_giphy_sdk_key="$GIPHY_SDK_KEY"
fi

LEGAL_URLS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.legal_urls|tojson' -)"
if [[ "$LEGAL_URLS" != "null" ]]; then
    export NOMAD_VAR_legal_urls="$(echo "$LEGAL_URLS" | jq -c)"
fi

TURNRELAY_HOST_ARRAY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
if [[ "$TURNRELAY_HOST_ARRAY" == "null" ]]; then
    TURNRELAY_HOST_ARRAY="$(cat $MAIN_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
fi

if [[ "$TURNRELAY_HOST_ARRAY" != "null" ]]; then
    export NOMAD_VAR_turnrelay_host="$(echo $TURNRELAY_HOST_ARRAY | yq eval '.[0]' -)"
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
# [ -n "$SHARD_STATE" ] && export NOMAD_VAR_shard_state="$SHARD_STATE"
export NOMAD_VAR_release_number="$RELEASE_NUMBER"
export NOMAD_VAR_signal_version="$SIGNAL_VERSION"
export NOMAD_VAR_jicofo_tag="$JICOFO_TAG"
export NOMAD_VAR_web_tag="$WEB_TAG"
export NOMAD_VAR_prosody_tag="$PROSODY_TAG"
export NOMAD_VAR_pool_type="$NOMAD_POOL_TYPE"
export NOMAD_VAR_branding_name="$BRANDING_NAME"

[ -z "$REGIONS" ] && REGIONS="$DRG_PEER_REGIONS"

NOMAD_DC="[]"
for ORACLE_REGION in $REGIONS; do
    NOMAD_DC="$( echo "$NOMAD_DC" "[\"$ENVIRONMENT-$ORACLE_REGION\"]" | jq -c -s '.|add')"
done

export NOMAD_VAR_dc="$NOMAD_DC"

sed -e "s/\[JOB_NAME\]/web-release-${RELEASE_NUMBER}/" "$NOMAD_JOB_PATH/jitsi-meet-web.hcl" | nomad job run -
