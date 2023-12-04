
[[ define "custom-config.js" -]]
var subdomainNoDot = '';
if (subdomain.endsWith('.')) {
  subdomainNoDot = subdomain.substr(0,subdomain.length-1)
  subdomain = subdomainNoDot;
}

config.p2p.useStunTurn=true;
{{ if ne "${var.jitsi_meet_p2p_preferred_codecs}" "" -}}
config.p2p.codecPreferenceOrder=${var.jitsi_meet_p2p_preferred_codecs};
{{ end -}}

config.useStunTurn=true;
config.enableSaveLogs=true;
config.disableRtx=false;
config.channelLastN=${var.channel_last_n};
config.flags.ssrcRewritingEnabled=${var.ssrc_rewriting_enabled};

{{ if eq "${var.restrict_hd_tile_view_jvb}" "true" -}}
config.maxFullResolutionParticipants = 1;
{{ end -}}

if (!config.hasOwnProperty('videoQuality')) config.videoQuality = {};
{{ if ne "${var.jitsi_meet_jvb_preferred_codecs}" "" -}}
config.videoQuality.codecPreferenceOrder=${var.jitsi_meet_jvb_preferred_codecs};
{{ end -}}

config.audioQuality.enableOpusDtx=${var.dtx_enabled};

{{ if eq "${var.hidden_from_recorder_feature}" "true" -}}
config.hiddenFromRecorderFeatureEnabled=true;
{{ end -}}

config.websocketKeepAliveUrl = 'https://<!--# echo var="http_host" default="${var.domain}" -->/<!--# echo var="subdir" default="" -->_unlock';

{{ if ne "${var.token_auth_url}" "" -}}
config.tokenAuthUrl=${var.token_auth_url};
{{ end -}}
{{ if eq "${var.token_auth_auto_redirect}" "true" -}}
config.tokenAuthUrlAutoRedirect=true;
{{ end -}}
{{ if ne "${var.token_logout_url}" "" -}}
config.tokenLogoutUrl='${var.token_logout_url}';
{{ end -}}
{{ if ne "${var.token_sso}" "" -}}
config.sso=${var.token_sso};
{{ end -}}

{{ if eq "${var.insecure_room_name_warning}" "true" -}}
config.enableInsecureRoomNameWarning=true;
{{ end -}}

if (!config.hasOwnProperty('analytics')) config.analytics = {};
{{ if ne "${var.amplitude_api_key}" "" -}}
config.analytics.amplitudeAPPKey="${var.amplitude_api_key}";
config.analytics.amplitudeIncludeUTM=${var.amplitude_include_utm};
{{ end -}}
config.analytics.rtcstatsEnabled=${var.rtcstats_enabled};
config.analytics.rtcstatsStoreLogs=${var.rtcstats_store_logs};
config.analytics.rtcstatsUseLegacy=${var.rtcstats_use_legacy};
config.analytics.rtcstatsEndpoint="${var.rtcstats_endpoint}";
config.analytics.rtcstatsPollInterval=${var.rtcstats_poll_interval};
config.analytics.rtcstatsSendSdp=${var.rtcstats_log_sdp};
{{ if ne "${var.amplitude_api_key}" "" -}}
config.analytics.whiteListedEvents=${var.analytics_white_listed_events};
{{ end -}}
{{ if ne "${var.video_resolution}" "" -}}
config.constraints.video.aspectRatio=16/9;
config.constraints.video.height={
  ideal: ${var.video_resolution},
  max: ${var.video_resolution},
  min: 180
};
config.constraints.video.width={
  ideal: {{ sprig_round (multiply ${var.video_resolution} (divide 9.0 16.0)) 0 }},
  max: {{ sprig_round (multiply ${var.video_resolution} (divide 9.0 16.0)) 0 }},
  min: 320
};
config.constraints.video.frameRate={max: 30, min: 15};
{{ end -}}

{{ if eq "${var.conference_request_http_enabled}" "true" -}}
config.conferenceRequestUrl='https://<!--# echo var="http_host" default="${var.domain}" -->/<!--# echo var="subdir" default="" -->conference-request/v1',
{{ end -}}


{{ if ne "${var.jaas_actuator_url}" "" -}}
config.jaasActuatorUrl='${var.jaas_actuator_url}',
{{ end -}}
{{ if ne "${var.api_jaas_token_url}" "" -}}
config.jaasTokenUrl='${var.api_jaas_token_url}',
{{ end -}}
{{ if ne "${var.jitsi_meet_api_jaas_conference_creator_url}" "" -}}
config.jaasConferenceCreatorUrl='${var.jitsi_meet_api_jaas_conference_creator_url}',
{{ end -}}
{{ if ne "${var.api_jaas_webhook_proxy}" "" -}}
config.webhookProxyUrl='${var.api_jaas_webhook_proxy }';
{{ end -}}
{{ if ne "${var.api_billing_counter}" "" -}}
config.billingCounterUrl='${var.api_billing_counter }';
{{ end -}}
{{ if ne "${var.api_branding_data_url}" "" -}}
config.brandingDataUrl='${var.api_branding_data_url }';
{{ end -}}
config.dialInNumbersUrl='${var.api_dialin_numbers_url }';
config.dialInConfCodeUrl= '${var.api_conference_mapper_url }';

{{ if ne "${var.api_dialout_codes_url}" "" -}}
config.dialOutCodesUrl= '${var.api_dialout_codes_url }';
{{ end -}}
{{ if ne "${var.api_dialout_auth_url}" "" -}}
config.dialOutAuthUrl='${var.api_dialout_auth_url }';
{{ end -}}
{{ if ne "${var.api_dialout_region_url}" "" -}}
config.dialOutRegionUrl='${var.api_dialout_region_url }';
{{ end -}}
{{ if ne "${var.api_directory_search_url}" "" -}}
config.peopleSearchUrl='${var.api_directory_search_url }';
{{ end -}}
{{ if ne "${var.api_conference_invite_url}" "" -}}
config.inviteServiceUrl='${var.api_conference_invite_url }';
{{ end -}}
{{ if ne "${var.api_conference_invite_callflows_url}" "" -}}
config.inviteServiceCallFlowsUrl='${var.api_conference_invite_callflows_url }';
{{ end -}}
{{ if ne "${var.api_guest_dial_out_url}" "" -}}
config.guestDialOutUrl='${var.api_guest_dial_out_url }';
{{ end -}}

{{ if ne "${var.api_guest_dial_out_status_url}" "" -}}
config.guestDialOutStatusUrl='${var.api_guest_dial_out_status_url }';
{{ end -}}

{{ if ne "${var.api_recoding_sharing_url}" "" -}}
config.recordingSharingUrl='${var.api_recoding_sharing_url }';
{{ end -}}

{{ if eq "${var.token_based_roles_enabled}" "true" -}}
config.enableUserRolesBasedOnToken=true;
{{ else -}}
config.enableUserRolesBasedOnToken=false;
{{ end -}}

{{ if eq "${var.forced_reloads_enabled}" "true" -}}
config.enableForcedReload=true;
{{ else -}}
config.enableForcedReload=false;
{{ end -}}

{{ if eq "${var.giphy_enabled}" "true" -}}
config.giphy={};
config.giphy.enabled=true;
config.giphy.sdkKey='${var.giphy_sdk_key}';
{{ end -}}

{{ if eq "${var.performance_stats_enabled}" "true" -}}
config.longTasksStatsInterval = 10000;
{{ end -}}

{{ if eq "${var.prejoin_page_enabled}" "true" -}}
config.prejoinPageEnabled=true;
{{ else -}}
config.prejoinPageEnabled=false;
{{ end -}}

{{ if ne "${var.moderated_service_url}" "" -}}
config.moderatedRoomServiceUrl='${var.moderated_service_url}';
{{ end -}}

config.deploymentInfo.releaseNumber='${var.release_number}';

config.mouseMoveCallbackInterval=1000;

config.screenshotCapture={
  enabled: ${var.screenshot_capture_enabled},
  mode: '${var.screenshot_capture_mode}'
};
config.toolbarConfig={
        timeout: 4000,
        initialTimeout: 20000
};

{{ if eq "${var.webhid_feature_enabled}" "true" -}}
config.enableWebHIDFeature=true;
{{ end -}}

{{ if eq "${var.iframe_api_disabled}" "true" -}}
config.disableIframeAPI=true;
{{ end -}}

config.faceLandmarks={
    enableFaceCentering: ${var.face_landmarks_centering_enabled},
    enableFaceExpressionsDetection: ${var.face_landmarks_detect_expressions},
    enableDisplayFaceExpressions: ${var.face_landmarks_display_expressions},
    enableRTCStats: ${var.face_landmarks_rtcstats_enabled},
    faceCenteringThreshold: 20,
    captureInterval: 1000
};

{{ if eq "${var.reactions_moderation_disabled}" "true" -}}
config.disableReactionsModeration=true;
{{ end -}}

{{ if eq "${var.turn_udp_enabled}" "true" -}}
config.useTurnUdp=true;
{{ end -}}

<!--#include virtual="config_deeplinking.js" -->

<!--#include virtual="config_legal.js" -->

[[ end -]]
