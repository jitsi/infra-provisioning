variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "web_tag" {
  type = string
}

variable "signal_version" {
  type = string
}

variable "dc" {
  type = list(string)
}

variable "release_number" {
  type = string
  default = "0"
}

variable "pool_type" {
  type = string
  default = "general"
}

variable web_repo {
  type = string
  default = "jitsi/web"
}

variable branding_name {
  type = string
  default = "jitsi-meet"
}

variable cloud_provider {
    type = string
    default = "oracle"
}

variable token_auth_url {
  type = string
  default = ""
}

variable token_auth_auto_redirect {
  type = string
  default = "false"
}

variable token_logout_url {
  type = string
  default = ""
}

variable token_sso {
  type = string
  default = ""
}

variable jvb_prefer_sctp {
  type = string
  default = "false"
}

variable insecure_room_name_warning {
  type = string
  default = "false"
}

variable amplitude_api_key {
  type = string
  default = ""
}

variable amplitude_include_utm {
  type = string
  default = "false"
}

variable rtcstats_enabled {
  type = string
  default = "false"
}

variable rtcstats_store_logs {
  type = string
  default = "false"
}

variable rtcstats_use_legacy {
  type = string
  default = "false"
}

variable rtcstats_endpoint {
  type = string
  default = ""
}

variable rtcstats_poll_interval {
  type = string
  default = "10000"
}

variable rtcstats_log_sdp {
  type = string
  default = "false"
}

variable analytics_white_listed_events {
  type = string
  default = ""
}

variable video_resolution {
  type = string
  default = ""
}

variable conference_request_http_enabled {
  type = string
  default = "false"
}

variable google_api_app_client_id {
  type = string
  default = ""
}

variable google_analytics_id {
  type = string
  default = ""
}

variable microsoft_api_app_client_id {
  type = string
  default = ""
}

variable dropbox_appkey {
  type = string
  default = ""
}

variable calendar_enabled {
  type = string
  default = "true"
}

variable token_based_roles_enabled {
  type = string
  default = "false"
}

variable invite_service_url {
  type = string
  default = ""
}

variable people_search_url {
  type = string
  default = ""
}

variable confcode_url {
  type = string
  default = ""
}

variable dialin_numbers_url {
  type = string
  default = ""
}

variable dialout_auth_url {
  type = string
  default = ""
}

variable dialout_codes_url {
  type = string
  default = ""
}

variable dialout_region_url {
  type = string
  default = ""
}

variable api_dialin_numbers_url {
  type = string
  default = ""
}

variable api_conference_mapper_url {
  type = string
  default = ""
}

variable api_dialout_auth_url {
  type = string
  default = ""
}

variable api_dialout_codes_url {
  type = string
  default = ""
}

variable api_dialout_region_url {
  type = string
  default = ""
}

variable api_directory_search_url {
  type = string
  default = ""
}

variable api_conference_invite_url {
  type = string
  default = ""
}

variable api_conference_invite_callflows_url {
  type = string
  default = ""
}

variable api_guest_dial_out_url {
  type = string
  default = ""
}

variable api_guest_dial_out_status_url {
  type = string
  default = ""
}

variable api_recoding_sharing_url {
  type = string
  default = ""
}

variable jaas_actuator_url {
  type = string
  default = ""
}

variable api_jaas_token_url {
  type = string
  default = ""
}

variable api_jaas_webhook_proxy {
  type = string
  default = ""
}

variable api_billing_counter {
  type = string
  default = ""
}

variable api_branding_data_url {
  type = string
  default = ""
}

variable channel_last_n {
  type = string
  default = "-1"
}

variable ssrc_rewriting_enabled {
  type = string
  default = "false"
}

variable restrict_hd_tile_view_jvb {
  type = string
  default = "false"
}

variable dtx_enabled {
  type = string
  default = "false"
}

variable hidden_from_recorder_feature {
  type = string
  default = "false"
}

variable transcriptions_enabled {
  type = string
  default = "false"
}

variable livestreaming_enabled {
  type = string
  default = "false"
}

variable service_recording_enabled {
  type = string
  default = "false"
}

variable service_recording_sharing_enabled {
  type = string
  default = "false"
}

variable local_recording_disabled {
  type = string
  default = "false"
}

variable require_display_name {
  type = string
  default = "false"
}

variable start_video_muted {
  type = number
  default = 25
}

variable start_audio_muted {
  type = number
  default = 25
}

variable forced_reloads_enabled {
  type = string
  default = "false"
}

variable legal_urls {
  type = string
  default = "{\"helpCentre\": \"https://web-cdn.jitsi.net/faq/meet-faq.html\", \"privacy\": \"https://jitsi.org/meet/privacy\", \"terms\": \"https://jitsi.org/meet/terms\"}"
}

variable whiteboard_enabled {
  type = string
  default = "false"
}

variable whiteboard_server_url {
  type = string
  default = ""
}

variable giphy_enabled {
  type = string
  default = "false"
}

variable giphy_sdk_key {
  type = string
  default = ""
}

variable performance_stats_enabled {
  type = string
  default = "false"
}

variable prejoin_page_enabled {
  type = string
  default = "false"
}

variable moderated_service_url {
  type = string
  default = ""
}

variable webhid_feature_enabled {
  type = string
  default = "true"
}

variable iframe_api_disabled {
  type = string
  default = "false"
}

variable screenshot_capture_enabled {
  type = string
  default = "false"
}

variable screenshot_capture_mode {
  type = string
  default = "recording"
}

variable face_landmarks_centering_enabled {
  type = string
  default = "false"
}

variable face_landmarks_detect_expressions {
  type = string
  default = "false"
}

variable face_landmarks_display_expressions {
  type = string
  default = "false"
}

variable face_landmarks_rtcstats_enabled {
  type = string
  default = "false"
}

variable reactions_moderation_disabled {
  type = string
  default = "false"
}

variable turn_udp_enabled {
  type = string
  default = "false"
}

variable jvb_preferred_codecs {
  type = string
  default = ""
}

variable p2p_preferred_codecs {
    type = string
    default = ""
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = var.dc

  spread {
    attribute = "${node.datacenter}"
  }

  type        = "service"

  meta {
    domain = "${var.domain}"
    web_tag = "${var.web_tag}"
    release_number = "${var.release_number}"
    environment = "${var.environment}"
    cloud_provider = "${var.cloud_provider}"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "web" {
    count = 2 * length(var.dc)

    update {
      max_parallel = 1
      health_check      = "checks"
    }

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    network {
      port "http" {
        to = 80
      }
      port "https" {
        to = 443
      }
      port "nginx-status" {
        to = 888
      }
    }

    service {
      name = "jitsi-meet-web"
      tags = ["release-${var.release_number}"]

      meta {
        domain = "${var.domain}"
        web_tag = "${var.web_tag}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
        http_backend_port = "${NOMAD_HOST_PORT_http}"
        nginx_status_ip = "${NOMAD_IP_nginx_status}"
        nginx_status_port = "${NOMAD_HOST_PORT_nginx_status}"
        signal_version = "${var.signal_version}"
        nomad_allocation = "${NOMAD_ALLOC_ID}"
      }

      port = "http"

      check {
        name     = "health"
        type     = "http"
        path     = "/nginx_status"
        port     = "nginx-status"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "web" {
      driver = "docker"
      config {
        image        = "${var.web_repo}:${var.web_tag}"
        ports = ["http","https","nginx-status"]
        volumes = [
          "local/_unlock:/usr/share/${var.branding_name}/_unlock",
          "local/config_deeplinking.js:/usr/share/${var.branding_name}/config_deeplinking.js",
          "local/config_legal.js:/usr/share/${var.branding_name}/config_legal.js",
          "local/nginx.conf:/defaults/nginx.conf",
          "local/config:/config",
          "local/nginx-status.conf:/config/nginx/site-confs/status.conf"
        ]
      }

      env {
        XMPP_DOMAIN = "${var.domain}"
        JVB_PREFER_SCTP = "${var.jvb_prefer_sctp}"
        PUBLIC_URL="https://${var.domain}/"
        XMPP_AUTH_DOMAIN = "auth.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
        DEPLOYMENTINFO_ENVIRONMENT = "${var.environment}"
        DEPLOYMENTINFO_SHARD = "release-${var.release_number}"
        DEPLOYMENTINFO_REGION = "${meta.cloud_region}"
        DEPLOYMENTINFO_USERREGION = "<!--# echo var=\"user_region\" default=\"\" -->"
        DISABLE_LOCAL_RECORDING = "${var.local_recording_disabled}"
        ENABLE_SIMULCAST = "true"
        ENABLE_RECORDING = "true"
        ENABLE_LIVESTREAMING = "${var.livestreaming_enabled}"
        ENABLE_SERVICE_RECORDING = "${var.service_recording_enabled}"
        ENABLE_FILE_RECORDING_SHARING = "${var.service_recording_sharing_enabled}"
        ENABLE_TALK_WHILE_MUTED = "true"
        ENABLE_CLOSE_PAGE = "true"
        ENABLE_GUESTS = "true"
        ENABLE_AUTH = "true"
        ENABLE_AUTH_DOMAIN = "false"
        ENABLE_IPV6 = "false"
        ENABLE_TRANSCRIPTIONS = "${var.transcriptions_enabled}"
        ENABLE_LOCAL_RECORDING_NOTIFY_ALL_PARTICIPANTS = "true"
        ENABLE_REQUIRE_DISPLAY_NAME = "${var.require_display_name}"
        WEBSOCKET_KEEPALIVE_URL = "https://${var.domain}/_unlock"
        ENABLE_CALENDAR = "${var.calendar_enabled}"
        GOOGLE_API_APP_CLIENT_ID = "${var.google_api_app_client_id}"
        MICROSOFT_API_APP_CLIENT_ID = "${var.microsoft_api_app_client_id}"
        DROPBOX_APPKEY = "${var.dropbox_appkey}"
        AMPLITUDE_ID = "${var.amplitude_api_key}"
        GOOGLE_ANALYTICS_ID = "${var.google_analytics_id}"
        INVITE_SERVICE_URL = "${var.invite_service_url}"
        PEOPLE_SEARCH_URL = "${var.people_search_url}"
        CONFCODE_URL = "${var.confcode_url}"
        DIALIN_NUMBERS_URL = "${var.dialin_numbers_url}"
        DIALOUT_AUTH_URL = "${var.dialout_auth_url}"
        DIALOUT_CODES_URL = "${var.dialout_codes_url}"
        START_VIDEO_MUTED = "${var.start_video_muted}"
        START_AUDIO_MUTED = "${var.start_audio_muted}"
        WHITEBOARD_ENABLED = "${var.whiteboard_enabled}"
        WHITEBOARD_COLLAB_SERVER_PUBLIC_URL = "${var.whiteboard_server_url}"
      }
      template {
        destination = "local/_unlock"
  data = <<EOF
OK
EOF
      }
//       template {
//         destination = "local/base.html"
//   data = <<EOF
// <base href=\"{{ jitsi_meet_cdn_base_url }}/{{ jitsi_meet_cdn_prefix }}{{ jitsi_meet_branding_version }}/\" />
// EOF
//       }
      template {
        destination = "local/nginx.conf"
        # overriding the delimiters to [[ ]] to avoid conflicts with tpl's native templating, which also uses {{ }}
        left_delimiter = "[["
        right_delimiter = "]]"

  data = <<EOF
user www-data;
worker_processes {{ .Env.NGINX_WORKER_PROCESSES | default "4" }};
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections {{ .Env.NGINX_WORKER_CONNECTIONS | default "768" }};
	# multi_accept on;
}

http {

	##
	# Basic Settings
	##

	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	server_tokens off;

	# server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

	client_max_body_size 0;

	{{ if .Env.NGINX_RESOLVER }}
	resolver {{ .Env.NGINX_RESOLVER }};
	{{ end -}}

 	include /etc/nginx/mime.types;
	types {
		# add support for wasm MIME type, that is required by specification and it is not part of default mime.types file
		application/wasm wasm;
		# add support for the wav MIME type that is requried to playback wav files in Firefox.
		audio/wav        wav;
	}
	default_type application/octet-stream;

	##
	# Logging Settings
	##

	access_log /dev/stdout;
	error_log /dev/stderr;

	##
	# Gzip Settings
	##

	gzip on;
	gzip_types text/plain text/css application/javascript application/json;
	gzip_vary on;
	gzip_min_length 860;

	##
	# Connection header for WebSocket reverse proxy
	##
	map $http_upgrade $connection_upgrade {
		default upgrade;
		''      close;
	}

  map $http_x_proxy_region $user_region {
      default '';
      us-west-2 us-west-2;
      us-east-1 us-east-1;
      us-east-2 us-east-2;
      us-west-1 us-west-1;
      ca-central-1 ca-central-1;
      eu-central-1 eu-central-1;
      eu-west-1 eu-west-1;
      eu-west-2 eu-west-2;
      eu-west-3 eu-west-3;
      eu-north-1 eu-north-1;
      me-south-1 me-south-1;
      ap-east-1 ap-east-1;
      ap-south-1 ap-south-1;
      ap-northeast-2 ap-northeast-2;
      ap-northeast-1 ap-northeast-1;
      ap-southeast-1 ap-southeast-1;
      ap-southeast-2 ap-southeast-2;
      sa-east-1 sa-east-1;
      ap-mumbai-1 ap-south-1;
      ap-sydney-1 ap-southeast-2;
      ap-tokyo-1 ap-northeast-1;
      ca-toronto-1 ca-central-1;
      eu-amsterdam-1 eu-west-3;
      eu-frankfurt-1 eu-central-1;
      me-jeddah-1 me-south-1;
      sa-saopaulo-1 sa-east-1;
      sa-vinhedo-1 sa-east-1;
      uk-london-1 eu-west-2;
      us-ashburn-1 us-east-1;
      us-phoenix-1 us-west-2;
  }

	##
	# Virtual Host Configs
	##
	include /config/nginx/site-confs/*;
}

daemon off;

EOF
    }

      template {
        data = <<EOF
server {
    listen 888 default_server;
    server_name  localhost;
    location /nginx_status {
        stub_status on;
        access_log off;
    }
}
EOF
        destination = "local/nginx-status.conf"
      }
      template {
        data = <<EOF


var subdomainNoDot = '';
if (subdomain.endsWith('.')) {
  subdomainNoDot = subdomain.substr(0,subdomain.length-1)
  subdomain = subdomainNoDot;
}

config.p2p.useStunTurn=true;
{{ if ne "${var.jitsi_meet_p2p_preferred_codecs}" "" -}}
config.p2p.codecPreferenceOrder='${var.p2p_preferred_codecs}';
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
{{ if ne "${var.jvb_preferred_codecs}" "" -}}
config.videoQuality.codecPreferenceOrder='${var.jvb_preferred_codecs}';
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

EOF
        destination = "local/config/custom-config.js"
      }

      template {
        data = file("nomad/templates/config_deeplinking.js")
        destination = "local/config_deeplinking.js"
      }

      template {
        data = file("nomad/templates/config_legal.js")
        destination = "local/config_legal.js"
      }

      template {
        data = <<EOF
#
# Basic configuration options
#

# Directory where all configuration will be stored
CONFIG=~/.jitsi-meet-cfg

# Exposed HTTP port
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}

# Exposed HTTPS port
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}

# System time zone
TZ=UTC

# XMPP domain for the jibri recorder

# XMPP recorder user for Jibri client connections
JIBRI_RECORDER_USER=recorder

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped
# overrides

ENABLE_LETSENCRYPT=0
ENABLE_XMPP_WEBSOCKET=1
DISABLE_HTTPS=1
#COLIBRI_WEBSOCKET_PORT={{ env "NOMAD_HOST_PORT_jvb_http_public" }}
EOF

        destination = "local/web.env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

  }
}