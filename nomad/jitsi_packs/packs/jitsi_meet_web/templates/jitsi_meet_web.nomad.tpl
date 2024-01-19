[[ template  "variables" . ]]

job [[ template "job_name" . ]] {
  region = "global"
  datacenters = var.dc

  spread {
    attribute = "${node.datacenter}"
  }

  type        = "service"

  meta {
    domain = "[[ env "CONFIG_domain" ]]"
    web_tag = "[[ env "CONFIG_web_tag" ]]"
    release_number = "[[ env "CONFIG_release_number" ]]"
    environment = "[[ env "CONFIG_environment" ]]"
    cloud_provider = "[[ or (env "CONFIG_cloud_provider") "oracle" ]]"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "web" {
    count = var.count_per_dc * length(var.dc)

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
      value     = "[[ or (env "CONFIG_pool_type") "general" ]]"
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
      tags = ["release-[[ env "CONFIG_release_number" ]]"]

      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        web_tag = "[[ env "CONFIG_web_tag" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
        http_backend_port = "${NOMAD_HOST_PORT_http}"
        nginx_status_ip = "${NOMAD_IP_nginx_status}"
        nginx_status_port = "${NOMAD_HOST_PORT_nginx_status}"
        signal_version = "[[ env "CONFIG_signal_version" ]]"
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
        image        = "[[ env "CONFIG_web_repo" ]]:[[ env "CONFIG_web_tag" ]]"
        ports = ["http","https","nginx-status"]
        volumes = [
          "local/_unlock:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/_unlock",
          "local/nginx.conf:/defaults/nginx.conf",
          "local/config:/config",
[[ if eq (env "CONFIG_jitsi_meet_load_test_enabled") "true" -]]
          "local/repo:/usr/share/nginx/html/load-test",
          "local/repo:/etc/nginx/html/load-test",
          "local/custom-meet.conf:/config/nginx/custom-meet.conf",
[[ end -]]
          "local/nginx-status.conf:/config/nginx/site-confs/status.conf"
        ]
      }

      env {
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        JVB_PREFER_SCTP = "[[ or (env "CONFIG_jitsi_meet_prefer_sctp") "false" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        XMPP_AUTH_DOMAIN = "auth.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.[[ env "CONFIG_domain" ]]"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        DEPLOYMENTINFO_ENVIRONMENT = "[[ env "CONFIG_environment" ]]"
        DEPLOYMENTINFO_SHARD = "release-[[ env "CONFIG_release_number" ]]"
        DEPLOYMENTINFO_REGION = "${meta.cloud_region}"
        DEPLOYMENTINFO_USERREGION = "<!--# echo var=\"user_region\" default=\"\" -->"
        DISABLE_LOCAL_RECORDING = "[[ if eq (env "CONFIG_jitsi_meet_enable_local_recording") "true" ]]false[[ else ]]true[[ end ]]"
        ENABLE_SIMULCAST = "true"
        ENABLE_RECORDING = "true"
        ENABLE_LIVESTREAMING = "[[ or (env "CONFIG_jitsi_meet_enable_livestreaming") "false" ]]"
        ENABLE_SERVICE_RECORDING = "[[ or (env "CONFIG_jitsi_meet_enable_file_recordings") "false" ]]"
        ENABLE_FILE_RECORDING_SHARING = "[[ or (env "CONFIG_jitsi_meet_enable_file_recordings_sharing") "false" ]]"
        ENABLE_TALK_WHILE_MUTED = "true"
        ENABLE_CLOSE_PAGE = "true"
        ENABLE_GUESTS = "true"
        ENABLE_AUTH = "true"
        ENABLE_AUTH_DOMAIN = "false"
        ENABLE_IPV6 = "false"
        ENABLE_TRANSCRIPTIONS = "[[ or (env "CONFIG_jitsi_meet_enable_transcription") "false" ]]"
        ENABLE_LOCAL_RECORDING_NOTIFY_ALL_PARTICIPANTS = "true"
        ENABLE_REQUIRE_DISPLAY_NAME = "[[ or (env "CONFIG_jitsi_meet_require_displayname") "false" ]]"
[[- if env "CONFIG_jitsi_meet_resolution" ]]
        RESOLUTION = "[[ or (env "CONFIG_jitsi_meet_resolution") "720" ]]"
        RESOLUTION_MIN = "[[ or (env "CONFIG_jitsi_meet_resolution_min") "180" ]]"
        RESOLUTION_WIDTH = "[[ or (env "CONFIG_jitsi_meet_resolution_width") "1280" ]]"
        RESOLUTION_WIDTH_MIN = "[[ or (env "CONFIG_jitsi_meet_resolution_width_min") "320" ]]"
[[- end ]]
        WEBSOCKET_KEEPALIVE_URL = "https://[[ env "CONFIG_domain" ]]/_unlock"
        ENABLE_CALENDAR = "[[ or (env "CONFIG_jitsi_meet_enable_calendar") "false" ]]"
        GOOGLE_API_APP_CLIENT_ID = "[[ env "CONFIG_jitsi_meet_google_api_app_client_id" ]]"
        MICROSOFT_API_APP_CLIENT_ID = "[[ env "CONFIG_jitsi_meet_microsoft_api_app_client_id" ]]"
        DROPBOX_APPKEY = "[[ env "CONFIG_jitsi_meet_dropbox_app_key" ]]"
        AMPLITUDE_ID = "[[ env "CONFIG_jitsi_meet_amplitude_api_key" ]]"
        GOOGLE_ANALYTICS_ID = "[[ if ne (or (env "CONFIG_jitsi_meet_google_analytics_flag") "false") "false" ]][[ env "CONFIG_jitsi_meet_google_analytics_tracking_id" ]][[ end ]]"
        INVITE_SERVICE_URL = "[[ env "CONFIG_jitsi_meet_api_conference_invite_url" ]]"
        PEOPLE_SEARCH_URL = "[[ env "CONFIG_jitsi_meet_api_directory_search_url" ]]"
        CONFCODE_URL = "[[ env "CONFIG_jitsi_meet_api_conference_mapper_url" ]]"
        DIALIN_NUMBERS_URL = "[[ env "CONFIG_jitsi_meet_api_dialin_numbers_url" ]]"
        DIALOUT_AUTH_URL = "[[ env "CONFIG_jitsi_meet_api_dialout_auth_url" ]]"
        DIALOUT_CODES_URL = "[[ env "CONFIG_jitsi_meet_api_dialout_codes_url" ]]"
        START_VIDEO_MUTED = "[[ or (env "CONFIG_jitsi_meet_start_video_muted_count") "25" ]]"
        START_AUDIO_MUTED = "[[ or (env "CONFIG_jitsi_meet_start_audio_muted_count") "25" ]]"
        TESTING_AV1_SUPPORT = "[[ env "CONFIG_jitsi_meet_enable_av1" ]]"
        WHITEBOARD_ENABLED = "[[ or (env "CONFIG_jitsi_meet_whiteboard_enabled") "false" ]]"
        WHITEBOARD_COLLAB_SERVER_PUBLIC_URL = "[[ env "CONFIG_jitsi_meet_whiteboard_collab_server_base_url" ]]"
      }

[[ if eq (env "CONFIG_jitsi_meet_load_test_enabled") "true" -]]
      artifact {
        source      = "https://github.com/jitsi/jitsi-meet-load-test/releases/download/0.0.1/release-0.0.1.zip"
        destination = "local/repo"
      }
      template {
        destination = "local/custom-meet.conf"
        data = <<EOF

    # load test minimal client, uncomment when used
    location ~ ^/_load-test/([^/?&:'"]+)$ {
        rewrite ^/_load-test/(.*)$ /load-test/index.html break;
    }
    location ~ ^/_load-test/libs/(.*)$ {
        add_header 'Access-Control-Allow-Origin' '*';
        alias /usr/share/nginx/html/load-test/libs/$1;
    }

    # load-test for subdomains
    location ~ ^/([^/?&:'"]+)/_load-test/([^/?&:'"]+)$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /load-test/index.html break;
    }

    # load-test for subdomains
    location ~ ^/([^/?&:'"]+)/_load-test/libs/(.*)$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        alias /usr/share/nginx/html/load-test/libs/$2;
    }
EOF

      }
[[ end -]]

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
        # overriding the delimiters to [< >] to avoid conflicts with tpl's native templating, which also uses {{ }}
        left_delimiter = "[<"
        right_delimiter = ">]"

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
[[ template  "custom-config.js" . ]]
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