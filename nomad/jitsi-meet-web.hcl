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
  type = string
}

variable "octo_region" {
    type=string
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

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"

  meta {
    domain = "${var.domain}"
    web_tag = "${var.web_tag}"
    release_number = "${var.release_number}"
    environment = "${var.environment}"
    octo_region = "${var.octo_region}"
    cloud_provider = "${var.cloud_provider}"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "web" {
    count = 2

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
          "local/base.html:/usr/share/${var.branding_name}/base.html",
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
        DEPLOYMENTINFO_REGION = "${var.octo_region}"
        DEPLOYMENTINFO_USERREGION = "<!--# echo var=\"user_region\" default=\"\" -->"
        ENABLE_SIMULCAST = "true"
        WEBSOCKET_KEEPALIVE_URL = "https://${var.domain}/_unlock"
        ENABLE_CALENDAR = "${var.calendar_enabled}"
        GOOGLE_API_APP_CLIENT_ID = "${var.google_api_app_client_id}"
        MICROSOFT_API_APP_CLIENT_ID = "${var.microsoft_api_app_client_id}"
        DROPBOX_APPKEY = "${var.dropbox_appkey}"
      }
      template {
        destination = "local/_unlock"
  data = <<EOF
OK
EOF
      }
      template {
        destination = "local/base.html"
  data = <<EOF

EOF
      }
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

EOF
        destination = "local/config/custom-config.js"
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