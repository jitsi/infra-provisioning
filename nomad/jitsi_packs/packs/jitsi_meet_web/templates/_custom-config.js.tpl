
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
config.enableSaveLogs=true;
config.disableRtx=false;
config.channelLastN=[[ env "CONFIG_jitsi_meet_channel_last_n" ]];
config.flags.ssrcRewritingEnabled=[[ env "CONFIG_jitsi_meet_enable_ssrc_rewriting" ]];

[[ if eq (env "CONFIG_jitsi_meet_restrict_HD_tile_view_jvb") "true" ]]
config.maxFullResolutionParticipants = 1;
[[- end ]]

if (!config.hasOwnProperty('videoQuality')) config.videoQuality = {};

[[ if env "CONFIG_jitsi_meet_jvb_preferred_codecs" -]]
config.videoQuality.codecPreferenceOrder=[[ env "CONFIG_jitsi_meet_jvb_preferred_codecs" ]];
[[- end ]]

config.audioQuality.enableOpusDtx=[[ env "CONFIG_jitsi_meet_enable_dtx" ]];

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
[[- end ]]

if (!config.hasOwnProperty('analytics')) config.analytics = {};

[[ if env "CONFIG_jitsi_meet_amplitude_api_key" -]]
config.analytics.amplitudeAPPKey="[[ env "CONFIG_jitsi_meet_amplitude_api_key" ]]";
config.analytics.amplitudeIncludeUTM=[[ or (env "CONFIG_jitsi_meet_amplitude_include_utm") "false" ]];
config.analytics.whiteListedEvents=[[ env "CONFIG_jitsi_meet_analytics_whitelist" ]];
[[- end ]]

config.analytics.rtcstatsEnabled=[[ or (env "CONFIG_jitsi_meet_rtcstats_enabled") "false" ]];
config.analytics.rtcstatsStoreLogs=[[ or (env "CONFIG_jitsi_meet_rtcstats_store_logs") "false" ]];
config.analytics.rtcstatsUseLegacy=[[ or (env "CONFIG_jitsi_meet_rtcstats_use_legacy") "false" ]];
config.analytics.rtcstatsEndpoint="[[ env "CONFIG_jitsi_meet_rtcstats_endpoint" ]];";
config.analytics.rtcstatsPollInterval=[[ or (env "CONFIG_jitsi_meet_rtcstats_poll_interval") "10000" ]];
config.analytics.rtcstatsSendSdp=[[ or (env "CONFIG_jitsi_meet_rtcstats_log_sdp") "false" ]];

[[ if env "CONFIG_jitsi_meet_resolution" -]]
config.constraints.video.aspectRatio=16/9;
config.constraints.video.height={
  ideal: [[ env "CONFIG_jitsi_meet_resolution" ]],
  max: [[ env "CONFIG_jitsi_meet_resolution" ]],
  min: 180
};
config.constraints.video.width={
  ideal: {{ sprig_round (multiply [[ env "CONFIG_jitsi_meet_resolution" ]] (divide 9.0 16.0)) 0 }},
  max: {{ sprig_round (multiply [[ env "CONFIG_jitsi_meet_resolution" ]] (divide 9.0 16.0)) 0 }},
  min: 320
};
config.constraints.video.frameRate={max: 30, min: 15};
[[- end ]]

[[ if eq (env "CONFIG_conference_request_http_enabled") "true" -]]
config.conferenceRequestUrl='https://<!--# echo var="http_host" default="[[ env "CONFIG_domain" ]]" -->/<!--# echo var="subdir" default="" -->conference-request/v1',
[[ end -]]

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
config.dialInNumbersUrl='[[ env "CONFIG_jitsi_meet_api_dialin_numbers_url" ]]';
config.dialInConfCodeUrl= '[[ env "CONFIG_jitsi_meet_api_conference_mapper_url" ]]';

[[ if env "CONFIG_jitsi_meet_api_dialout_codes_url" -]]
config.dialOutCodesUrl= '[[ env "CONFIG_jitsi_meet_api_dialout_codes_url" ]]';
[[- end ]]

[[ if env "CONFIG_jitsi_meet_api_dialout_auth_url" -]]
config.dialOutAuthUrl='[[ env "CONFIG_jitsi_meet_api_dialout_auth_url" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_api_dialout_region_url" -]]
config.dialOutRegionUrl='[[ env "CONFIG_jitsi_meet_api_dialout_region_url" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_api_directory_search_url" -]]
config.peopleSearchUrl='[[ env "CONFIG_jitsi_meet_api_directory_search_url" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_api_conference_invite_url" -]]
config.inviteServiceUrl='[[ env "CONFIG_jitsi_meet_api_conference_invite_url" ]]';
[[- end ]]
[[ if env "CONFIG_jitsi_meet_api_conference_invite_callflows_url" -]]
config.inviteServiceCallFlowsUrl='[[ env "CONFIG_jitsi_meet_api_conference_invite_callflows_url" ]]';
[[- end ]]
[[ if and (env "CONFIG_jitsi_meet_api_guest_dial_out_url") (ne (env "CONFIG_jitsi_meet_api_guest_dial_out_url") "false") -]]
config.guestDialOutUrl='[[ env "CONFIG_jitsi_meet_api_guest_dial_out_url" ]]';
[[- end ]]
[[ if and (env "CONFIG_jitsi_meet_api_guest_dial_out_status_url") (ne (env "CONFIG_jitsi_meet_api_guest_dial_out_status_url") "false") -]]
config.guestDialOutStatusUrl='[[ env "CONFIG_jitsi_meet_api_guest_dial_out_status_url" ]]';
[[- end ]]

[[ if env "CONFIG_jitsi_meet_api_recoding_sharing_url" -]]
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

[[ if eq (env "CONFIG_jitsi_meet_enable_webhid_feature") "true" -]]
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

[[ template "config_deeplinking.js" . ]]

[[ template "config_legal.js" . ]]

[[ end -]]
