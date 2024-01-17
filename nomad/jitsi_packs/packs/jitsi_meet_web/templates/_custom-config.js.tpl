
[[ define "custom-config.js" -]]
var subdomainNoDot = '';
if (subdomain.endsWith('.')) {
  subdomainNoDot = subdomain.substr(0,subdomain.length-1)
  subdomain = subdomainNoDot;
}

config.p2p.useStunTurn=true;
[[ if env "CONFIG_jitsi_meet_p2p_preferred_codecs" -]]
config.p2p.codecPreferenceOrder=[[ env "CONFIG_jitsi_meet_p2p_preferred_codecs" ]];
[[- end ]]

config.useStunTurn=true;
config.enableSaveLogs=[[ or (env "CONFIG_jitsi_meet_enable_save_logs") "true" ]];
config.channelLastN=[[ or (env "CONFIG_jitsi_meet_channel_last_n") "-1" ]];
config.flags.ssrcRewritingEnabled=[[ or (env "CONFIG_jitsi_meet_enable_ssrc_rewriting") "false" ]];

[[ if eq (env "CONFIG_jitsi_meet_restrict_HD_tile_view_jvb") "true" ]]
config.maxFullResolutionParticipants = 1;
[[- end ]]

[[ if env "CONFIG_jitsi_meet_jvb_preferred_codecs" -]]
if (!config.hasOwnProperty('videoQuality')) config.videoQuality = {};
config.videoQuality.codecPreferenceOrder=[[ env "CONFIG_jitsi_meet_jvb_preferred_codecs" ]];
[[- end ]]

config.audioQuality.enableOpusDtx=[[ or (env "CONFIG_jitsi_meet_enable_dtx") "false" ]];

[[ if eq (env "CONFIG_jitsi_meet_hidden_from_recorder_feature") "true" -]]
config.hiddenFromRecorderFeatureEnabled=true;
[[- end ]]

config.websocketKeepAliveUrl = 'https://<!--# echo var="http_host" default="[[ env "CONFIG_domain" ]]" -->/<!--# echo var="subdir" default="" -->_unlock';

[[ if env "CONFIG_jitsi_meet_token_auth_url" -]]
config.tokenAuthUrl=[[ env "CONFIG_jitsi_meet_token_auth_url" ]];
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_token_auth_url_auto_redirect") "true" -]]
config.tokenAuthUrlAutoRedirect=true;
[[- end ]]
[[ if env "CONFIG_jitsi_meet_token_logout_url" -]]
config.tokenLogoutUrl='[[ env "CONFIG_jitsi_meet_token_logout_url" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_token_sso" -]]
config.sso=[[ env "CONFIG_jitsi_meet_token_sso" ]];
[[- end ]]


[[ if eq (env "CONFIG_jitsi_meet_enable_unsafe_room_warning") "true" -]]
config.enableInsecureRoomNameWarning=true;
[[- else ]]
config.enableInsecureRoomNameWarning=false;
[[- end ]]

if (!config.hasOwnProperty('analytics')) config.analytics = {};

[[ if env "CONFIG_jitsi_meet_amplitude_api_key" -]]
config.analytics.amplitudeAPPKey="[[ env "CONFIG_jitsi_meet_amplitude_api_key" ]]";
config.analytics.amplitudeIncludeUTM=[[ or (env "CONFIG_jitsi_meet_amplitude_include_utm") "false" ]];
config.analytics.whiteListedEvents=[[ or (env "CONFIG_jitsi_meet_analytics_whitelist") "[]" ]];
[[- end ]]

config.analytics.rtcstatsEnabled=[[ or (env "CONFIG_jitsi_meet_rtcstats_enabled") "false" ]];
config.analytics.rtcstatsStoreLogs=[[ or (env "CONFIG_jitsi_meet_rtcstats_store_logs") "false" ]];
config.analytics.rtcstatsUseLegacy=[[ or (env "CONFIG_jitsi_meet_rtcstats_use_legacy") "false" ]];
config.analytics.rtcstatsEndpoint="[[ env "CONFIG_jitsi_meet_rtcstats_endpoint" ]]";
config.analytics.rtcstatsPollInterval=[[ or (env "CONFIG_jitsi_meet_rtcstats_poll_interval") "10000" ]];
config.analytics.rtcstatsSendSdp=[[ or (env "CONFIG_jitsi_meet_rtcstats_log_sdp") "false" ]];

config.constraints.video.aspectRatio=16/9;
config.constraints.video.frameRate={max: 30, min: 15};

[[ if eq (env "CONFIG_jitsi_meet_enable_conference_request_http") "true" -]]
config.conferenceRequestUrl='https://<!--# echo var="http_host" default="[[ env "CONFIG_domain" ]]" -->/<!--# echo var="subdir" default="" -->conference-request/v1';
[[ end -]]


if (!config.hasOwnProperty('deploymentUrls')) config.deploymentUrls = {};
[[ if env "CONFIG_jitsi_meet_user_documentation_url" -]]
config.deploymentUrls.userDocumentationURL='[[ env "CONFIG_jitsi_meet_user_documentation_url" ]]';
[[ end -]]
[[ if env "CONFIG_jitsi_meet_download_apps_url" -]]
config.deploymentUrls.downloadAppsUrl='[[ env "CONFIG_jitsi_meet_download_apps_url" ]]'; 
[[- end ]]

[[ if ne (or (env "CONFIG_jitsi_meet_chrome_extension_banner_url") "false") "false" -]]
config.chromeExtensionBanner = {
        url: "[[ env "CONFIG_jitsi_meet_chrome_extension_banner_url" ]]",
[[ if ne (or (env "CONFIG_jitsi_meet_edge_extension_banner_url") "false") "false" -]]
        edgeUrl: "[[ env "CONFIG_jitsi_meet_edge_extension_banner_url" ]]",
[[- end ]]
[[ if ne (or (env "CONFIG_jitsi_meet_chrome_extension_info") "false") "false" -]]
        chromeExtensionsInfo: [[ env "CONFIG_jitsi_meet_chrome_extension_info" ]]
[[- end ]]
    };
[[- end ]]

[[ if env "CONFIG_prosody_jaas_actuator_url" -]]
config.jaasActuatorUrl='[[ env "CONFIG_prosody_jaas_actuator_url" ]]',
[[ end -]]
[[ if env "CONFIG_jitsi_meet_api_jaas_token_url" -]]
config.jaasTokenUrl='[[ env "CONFIG_jitsi_meet_api_jaas_token_url" ]]',
[[ end -]]
[[ if env "CONFIG_jitsi_meet_api_jaas_conference_creator_url" -]]
config.jaasConferenceCreatorUrl='[[ env "CONFIG_jitsi_meet_api_jaas_conference_creator_url" ]]',
[[ end -]]
[[ if env "CONFIG_jitsi_meet_api_jaas_webhook_proxy" -]]
config.webhookProxyUrl='[[ env "CONFIG_jitsi_meet_api_jaas_webhook_proxy" ]]',
[[ end -]]
[[ if env "CONFIG_jitsi_meet_api_billing_counter" -]]
config.billingCounterUrl='[[ env "CONFIG_jitsi_meet_api_billing_counter" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_api_branding_data_url" -]]
config.brandingDataUrl='[[ env "CONFIG_jitsi_meet_api_branding_data_url" ]]';
[[- end ]]
config.dialInNumbersUrl='[[ or (env "CONFIG_jitsi_meet_api_dialin_numbers_url") "https://api.jitsi.net/phoneNumberList" ]]';
config.dialInConfCodeUrl= '[[ or (env "CONFIG_jitsi_meet_api_conference_mapper_url") "https://api.jitsi.net/conferenceMapper" ]]';

[[ if ne (env "CONFIG_jitsi_meet_api_dialout_codes_url") "false" -]]
config.dialOutCodesUrl= '[[ or (env "CONFIG_jitsi_meet_api_dialout_codes_url") "https://api.jitsi.net/countrycodes" ]]';
[[- end ]]

[[ if ne (env "CONFIG_jitsi_meet_api_dialout_auth_url") "false" -]]
config.dialOutAuthUrl='[[ or (env "CONFIG_jitsi_meet_api_dialout_auth_url") "https://api.jitsi.net/authorizephone" ]]';
[[- end ]]
[[ if ne (env "CONFIG_jitsi_meet_api_dialout_region_url") "false" -]]
config.dialOutRegionUrl='[[ or (env "CONFIG_jitsi_meet_api_dialout_region_url") "https://api.jitsi.net/outbounddestination" ]]';
[[- end ]]
[[ if ne (env "CONFIG_jitsi_meet_api_directory_search_url") "false" -]]
config.peopleSearchUrl='[[ or (env "CONFIG_jitsi_meet_api_directory_search_url") "https://api.jitsi.net/directorySearch" ]]';
[[- end ]]
[[ if ne (env "CONFIG_jitsi_meet_api_conference_invite_url") "false" -]]
config.inviteServiceUrl='[[ or (env "CONFIG_jitsi_meet_api_conference_invite_url") "https://api.jitsi.net/conferenceInvite" ]]';
[[- end ]]
[[ if ne (env "CONFIG_jitsi_meet_api_conference_invite_callflows_url") "false" -]]
config.inviteServiceCallFlowsUrl='[[ or (env "CONFIG_jitsi_meet_api_conference_invite_callflows_url") "https://api.jitsi.net/conferenceinvitecallflows" ]]';
[[- end ]]
[[ if and (env "CONFIG_jitsi_meet_api_guest_dial_out_url") (ne (env "CONFIG_jitsi_meet_api_guest_dial_out_url") "false") -]]
config.guestDialOutUrl='[[ env "CONFIG_jitsi_meet_api_guest_dial_out_url" ]]';
[[- end ]]
[[ if and (env "CONFIG_jitsi_meet_api_guest_dial_out_status_url") (ne (env "CONFIG_jitsi_meet_api_guest_dial_out_status_url") "false") -]]
config.guestDialOutStatusUrl='[[ env "CONFIG_jitsi_meet_api_guest_dial_out_status_url" ]]';
[[- end ]]
[[ if and (env "CONFIG_jitsi_meet_api_recoding_sharing_url") (ne (env "CONFIG_jitsi_meet_api_recoding_sharing_url") "false")  -]]
config.recordingSharingUrl='[[ env "CONFIG_jitsi_meet_api_recoding_sharing_url" ]]';
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_enable_user_roles_based_on_token") "true" -]]
config.enableUserRolesBasedOnToken=true;
[[ else -]]
config.enableUserRolesBasedOnToken=false;
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_enable_forced_client_reload") "true" -]]
config.enableForcedReload=true;
[[ else -]]
config.enableForcedReload=false;
[[- end ]]


[[ if eq (env "CONFIG_jitsi_meet_giphy_enabled") "true" -]]
config.giphy={};
config.giphy.enabled=true;
config.giphy.sdkKey='[[ env "CONFIG_jitsi_meet_giphy_sdk_key" ]]';
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_performance_stats") "true" -]]
config.longTasksStatsInterval = 10000;
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_enable_prejoin_page") "true" -]]
config.prejoinPageEnabled=true;
[[ else -]]
config.prejoinPageEnabled=false;
[[- end ]]


[[ if env "CONFIG_jitsi_meet_moderated_service_url" -]]
config.moderatedRoomServiceUrl='[[ env "CONFIG_jitsi_meet_moderated_service_url" ]]';
[[- end ]]

config.deploymentInfo.releaseNumber='[[ env "CONFIG_release_number" ]]';

config.mouseMoveCallbackInterval=1000;

config.screenshotCapture={
  enabled: [[ or (env "CONFIG_jitsi_meet_screenshot_capture_enabled") "false" ]],
  mode: '[[ or (env "CONFIG_jitsi_meet_screenshot_capture_mode") "recording" ]]'
};
config.toolbarConfig={
        timeout: 4000,
        initialTimeout: 20000
};

[[ if eq (or (env "CONFIG_jitsi_meet_enable_webhid_feature") "true") "true" -]]
config.enableWebHIDFeature=true;
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_disable_iframe_api") "true" -]]
config.disableIframeAPI=true;
[[- end ]]

config.faceLandmarks={
    enableFaceCentering: [[ or (env "CONFIG_jitsi_meet_enable_face_landmarks_enable_centering") "false" ]],
    enableFaceExpressionsDetection: [[ or (env "CONFIG_jitsi_meet_enable_face_landmarks_detect_expressions") "false" ]],
    enableDisplayFaceExpressions: [[ or (env "CONFIG_jitsi_meet_enable_face_landmarks_display_expressions") "false" ]],
    enableRTCStats: [[ or (env "CONFIG_jitsi_meet_enable_face_landmarks_enable_rtc_stats") "false" ]],
    faceCenteringThreshold: 20,
    captureInterval: 1000
};

[[ if eq (env "CONFIG_jitsi_meet_disable_reactions_moderation") "true" -]]
config.disableReactionsModeration=true;
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_enable_turn_udp_jvb") "true" -]]
config.useTurnUdp=true;
[[- end ]]

[[ if and (env "CONFIG_jitsi_meet_cors_avatar_urls") (ne (env "CONFIG_jitsi_meet_cors_avatar_urls") "false") ]]
config.corsAvatarURLs=[[ env "CONFIG_jitsi_meet_cors_avatar_urls" ]],
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_enable_lock_room_ten_digits") "true"]]
config.roomPasswordNumberOfDigits=10;
[[- end ]]

[[ if (env "CONFIG_jitsi_meet_api_screenshot_history_url") -]]
config._screenshotHistoryUrl='[[ env "CONFIG_jitsi_meet_api_screenshot_history_url" ]]';
[[- end ]]
[[ if (env "CONFIG_jitsi_meet_api_screenshot_history_region_url") -]]
config._screenshotHistoryRegionUrl='[[ env "CONFIG_jitsi_meet_api_screenshot_history_region_url" ]]';
[[- end ]]
[[ if (env "CONFIG_jitsi_meet_api_sip_invite_url") -]]
config.sipInviteUrl='[[ env "CONFIG_jitsi_meet_api_sip_invite_url" ]]';
[[- end ]]

[[ if eq (env "CONFIG_jitsi_meet_conference_info_overwrite") "true" -]]
config.conferenceInfo = {
        alwaysVisible: [[ or (env "CONFIG_jitsi_meet_conference_info_visible") "[ 'recording', 'local-recording', 'raised-hands-count' ]" ]],
        autoHide: [[ or (env "CONFIG_jitsi_meet_conference_info_autohide") "[ 'highlight-moment', 'subject', 'conference-timer', 'participants-count', 'e2ee', 'transcribing', 'video-quality', 'insecure-room' ]" ]]
};
[[- end ]]

[[ if (env "CONFIG_jaas_feedback_metadata_url") -]]
config.jaasFeedbackMetadataURL='[[ env "CONFIG_jaas_feedback_metadata_url" ]]';
[[- end ]]

config.speakerStats = {
    disableSearch: [[ if eq (env "CONFIG_jitsi_meet_disable_speaker_stats_search") "true" ]]true[[ else ]]false[[ end ]]
};

if (!config.hasOwnProperty('whiteboard')) config.whiteboard = {};
config.whiteboard.userLimit = [[ or (env "CONFIG_jitsi_meet_whiteboard_user_limit") "25" ]];

[[ template "config_deeplinking.js" . ]]

[[ if (env "CONFIG_legal_urls") -]]
config.legalUrls = [[ env "CONFIG_legal_urls" ]];
[[ else -]]
[[ template "config_legal.js" . ]]
[[ end -]]

[[ end -]]
