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
    count = 1

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
        volumes = ["local/_unlock:/usr/share/${var.branding_name}/_unlock","local/base.html:/usr/share/${var.branding_name}/base.html","local/nginx.conf:/defaults/nginx.conf","local/nginx-status.conf:/config/nginx/site-confs/status.conf"]
      }

      env {
        XMPP_DOMAIN = "${var.domain}"
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