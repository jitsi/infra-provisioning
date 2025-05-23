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
      operator     = "set_contains_any"
      value    = "consul,general,shard"
    }

[[ if ne (env "CONFIG_pool_type") "consul" ]]
    affinity {
      attribute  = "${meta.pool_type}"
      operator = "="
      value     = "consul"
      weight    = -100
    }
[[ end ]]
[[ if ne (env "CONFIG_pool_type") "general" ]]
    affinity {
      attribute  = "${meta.pool_type}"
      operator = "="
      value     = "general"
      weight    = -50
    }
[[ end ]]
    affinity {
      attribute  = "${meta.pool_type}"
      value     = "[[ or (env "CONFIG_pool_type") "shard" ]]"
      operator = "="
      weight    = 100
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
[[ if eq (env "CONFIG_jitsi_meet_cdn_cloudflare_enabled") "true" -]]
          "local/init-cdn:/etc/cont-init.d/11-init-cdn",
[[ end -]]
          "local/_unlock:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/_unlock",
          "local/_unlock:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/_health",
          "local/nginx.conf:/defaults/nginx.conf",
          "local/config:/config",
[[ if eq (env "CONFIG_jitsi_meet_load_test_enabled") "true" -]]
          "local/repo:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/load-test",
[[ end -]]
          "local/well-known/apple-app-site-association:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/apple-app-site-association",
          "local/well-known:/usr/share/[[ or (env "CONFIG_jitsi_meet_branding_override") "jitsi-meet" ]]/.well-known",
          "local/nginx-status.conf:/config/nginx/site-confs/status.conf"
        ]
        labels {
          release = "[[ env "CONFIG_release_number" ]]"
          version = "[[ env "CONFIG_web_tag" ]]"
        }
      }

      env {
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        JVB_PREFER_SCTP = "[[ or (env "CONFIG_jitsi_meet_prefer_sctp") "true" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        XMPP_AUTH_DOMAIN = "auth.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.[[ env "CONFIG_domain" ]]"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        XMPP_HIDDEN_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        DEPLOYMENTINFO_ENVIRONMENT = "[[ env "CONFIG_environment" ]]"
        DEPLOYMENTINFO_SHARD = "release-[[ env "CONFIG_release_number" ]]"
        DEPLOYMENTINFO_REGION = "${meta.cloud_region}"
        DISABLE_LOCAL_RECORDING = "[[ if eq (env "CONFIG_jitsi_meet_enable_local_recording") "true" ]]false[[ else ]]true[[ end ]]"
        ENABLE_SIMULCAST = "true"
        ENABLE_RECORDING = "true"
        ENABLE_LOAD_TEST_CLIENT = "[[ or (env "CONFIG_jitsi_meet_load_test_enabled") "false" ]]"
        ENABLE_LIVESTREAMING = "[[ or (env "CONFIG_jitsi_meet_enable_livestreaming") "false" ]]"
        ENABLE_SERVICE_RECORDING = "[[ or (env "CONFIG_jitsi_meet_enable_file_recordings") "false" ]]"
        ENABLE_FILE_RECORDING_SHARING = "[[ or (env "CONFIG_jitsi_meet_enable_file_recordings_sharing") "false" ]]"
        ENABLE_TALK_WHILE_MUTED = "true"
        ENABLE_CLOSE_PAGE = "true"
        ENABLE_GUESTS = "[[ if ne (or (env "CONFIG_jitsi_meet_anonymousdomain") "false") "false" ]]true[[ end ]]"
        ENABLE_AUTH = "true"
        ENABLE_AUTH_DOMAIN = "false"
        ENABLE_IPV6 = "false"
        ENABLE_TRANSCRIPTIONS = "[[ or (env "CONFIG_jitsi_meet_enable_transcription") "false" ]]"
        ENABLE_LOCAL_RECORDING_NOTIFY_ALL_PARTICIPANT = "true"
        ENABLE_REQUIRE_DISPLAY_NAME = "[[ or (env "CONFIG_jitsi_meet_require_displayname") "false" ]]"
        FILESHARING_API_URL = "[[ env "CONFIG_jitsi_meet_filesharing_api_url" ]]"
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
        START_VIDEO_MUTED = "[[ or (env "CONFIG_jitsi_meet_start_video_muted_count") "25" ]]"
        START_AUDIO_MUTED = "[[ or (env "CONFIG_jitsi_meet_start_audio_muted_count") "25" ]]"
        WHITEBOARD_ENABLED = "[[ or (env "CONFIG_jitsi_meet_whiteboard_enabled") "false" ]]"
        WHITEBOARD_COLLAB_SERVER_PUBLIC_URL = "[[ env "CONFIG_jitsi_meet_whiteboard_collab_server_base_url" ]]"
        WEB_CONFIG_PREFIX="/**\n * Hey there Hacker One bounty hunters! None of the contents of this file are security sensitive.\n * Sorry, but your princess is in another castle :-)\n * Happy hunting!\n*/\n"
      }

[[ if eq (env "CONFIG_jitsi_meet_load_test_enabled") "true" -]]
      artifact {
        source      = "https://github.com/jitsi/jitsi-meet-load-test/releases/download/0.0.1/release-0.0.1.zip"
        destination = "local/repo"
      }
[[ end -]]
      template {
        destination = "local/well-known/apple-app-site-association"
  data = <<EOF
[[ env "CONFIG_jitsi_meet_apple_site_associations" ]]
EOF
      }
      template {
        destination = "local/well-known/assetlinks.json"
  data = <<EOF
[[ env "CONFIG_jitsi_meet_assetlinks" ]]
EOF
      }

      template {
        destination = "local/_unlock"
  data = <<EOF
OK
EOF
      }
[[ if eq (env "CONFIG_jitsi_meet_cdn_cloudflare_enabled") "true" ]]
      template {
        destination = "local/init-cdn"
        perms = "0755"
        data = <<EOF
#!/bin/sh
sed -i -e "s/web-cdn.jitsi.net/[[ env "CONFIG_domain" ]]\/v1\/_cdn/" /usr/share/*/base.html
EOF
      }
[[ end ]]
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

	# client_max_body_size 0;

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
