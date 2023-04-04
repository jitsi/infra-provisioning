variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "jicofo_tag" {
  type = string
}
variable "web_tag" {
  type = string
}
variable "prosody_tag" {
  type = string
}

variable "signal_version" {
  type = string
}

variable "dc" {
  type = string
}

variable "shard" {
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

variable jicofo_auth_password {
    type = string
    default = "replaceme_jicofo"
}

variable jvb_auth_password {
    type = string
    default = "replaceme_jvb"
}

variable jigasi_xmpp_password {
    type = string
    default = "replaceme_jigasi"
}

variable jibri_recorder_password {
    type = string
    default = "replaceme_recorder"
}

variable jibri_xmpp_password {
    type = string
    default = "replaceme_jibri"
}

variable enable_auto_owner {
    type = string
    default = "false"
}

variable enable_muc_allowners {
    type = string
    default = "false"
}

variable cloud_provider {
    type = string
    default = "oracle"
}

variable jwt_asap_keyserver {
    type = string
    default = "asap.example.com"
}

variable jwt_accepted_issuers {
    type = string
    default = "jitsi"
}

variable jwt_accepted_audiences {
    type = string
    default = "jitsi"
}

variable turnrelay_host {
  type = string
  default = "turn.example.com"
}

variable turnrelay_password {
  type = string
  default = "password"
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"

  meta {
    domain = "${var.domain}"
    shard = "${var.shard}"
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

  group "signal" {
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
      port "prosody-http" {
        to = 5280
      }
      port "signal-sidecar-agent" {
      }
      port "signal-sidecar-http" {
      }
      port "prosody-client" {
      }
      port "prosody-jvb-client" {
      }
      port "prosody-jvb-http" {
        to = 5280
      }
      port "jicofo-http" {
        to = 8888
      }
    }

    service {
      name = "signal"
      tags = ["${var.domain}","shard-${var.shard}","release-${var.release_number}","urlprefix-/${var.shard}/"]

      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        shard_id = "${var.shard_id}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
        http_backend_port = "${NOMAD_HOST_PORT_http}"
        prosody_http_ip = "${NOMAD_IP_prosody_http}"
        nginx_status_ip = "${NOMAD_IP_nginx_status}"
        nginx_status_port = "${NOMAD_HOST_PORT_nginx_status}"
        prosody_client_ip = "${NOMAD_IP_prosody_client}"
        prosody_http_port = "${NOMAD_HOST_PORT_prosody_http}"
        prosody_client_port = "${NOMAD_HOST_PORT_prosody_client}"
        prosody_jvb_client_port = "${NOMAD_HOST_PORT_prosody_jvb_client}"
        signal_sidecar_agent_port = "${NOMAD_HOST_PORT_signal_sidecar_agent}"
        signal_sidecar_http_ip = "${NOMAD_IP_signal_sidecar_http}"
        signal_sidecar_http_port = "${NOMAD_HOST_PORT_signal_sidecar_http}"
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

    service {
      name = "jicofo"
      tags = ["${var.shard}", "${var.environment}","ip-${attr.unique.network.ip-address}"]
      port = "jicofo-http"

      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
      }
    }

    service {
      name = "prosody-http"
      tags = ["${var.shard}","ip-${attr.unique.network.ip-address}"]
      port = "prosody-http"
      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/http-bind"
        port     = "prosody-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "prosody-jvb-http"
      tags = ["${var.shard}","ip-${attr.unique.network.ip-address}"]
      port = "prosody-jvb-http"
      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/http-bind"
        port     = "prosody-jvb-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "signal-sidecar"
      tags = ["${var.shard}","ip-${attr.unique.network.ip-address}","urlprefix-/${var.shard}/about/health strip=/${var.shard}"]
      port = "signal-sidecar-http"
      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/health"
        port     = "signal-sidecar-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {

      name = "prosody-client"
      tags = ["${var.shard}"]

      port = "prosody-client"

      check {
        name = "health"
        type = "tcp"
        port = "prosody-client"
        interval = "10s"
        timeout = "2s"
      }
    }

    service {

      name = "prosody-jvb-client"
      tags = ["${var.shard}"]
      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        environment = "${meta.environment}"
      }

      port = "prosody-jvb-client"

      check {
        name = "health"
        type = "tcp"
        port = "prosody-jvb-client"
        interval = "10s"
        timeout = "2s"
      }
    }


    task "signal-sidecar" {
      driver = "docker"
      config {
        image        = "jitsi/signal-sidecar:latest"
        ports = ["signal-sidecar-agent","signal-sidecar-http"]
      }

      env {
        CENSUS_POLL = true
        CONSUL_SECURE = false
        CONSUL_PORT=8500
        CONSUL_STATUS = true
        CONSUL_REPORTS = true
        CONSUL_STATUS_KEY = "shard-states/${var.environment}/${var.shard}"
        CONSUL_REPORT_KEY = "signal-report/${var.environment}/${var.shard}"
      }
      template {
          data = <<EOF
CONSUL_HOST={{ env "attr.unique.network.ip-address" }}
HTTP_PORT={{ env "NOMAD_HOST_PORT_signal_sidecar_http" }}
TCP_PORT={{ env "NOMAD_HOST_PORT_signal_sidecar_agent" }}
CENSUS_HOST={{ env "NOMAD_META_domain" }}
JICOFO_ORIG=http://{{ env "NOMAD_IP_jicofo_http" }}:{{ env "NOMAD_HOST_PORT_jicofo_http" }}
PROSODY_ORIG=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}
EOF

        destination = "local/signal-sidecar.env"
        env = true
      }
    }
    task "web" {
      driver = "docker"
      config {
        image        = "jitsi/web:${var.web_tag}"
        ports = ["http","https","nginx-status"]
        volumes = ["local/base.html:/usr/share/jitsi-meet/base.html","local/nginx.conf:/defaults/nginx.conf","local/nginx-status.conf:/config/nginx/site-confs/status.conf"]
      }

      env {
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JICOFO_AUTH_PASSWORD = "${var.jicofo_auth_password}"
        JVB_AUTH_PASSWORD = "${var.jvb_auth_password}"
        JIGASI_XMPP_PASSWORD = "${var.jigasi_xmpp_password}"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
        # Internal XMPP domain for authenticated services
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
        DEPLOYMENTINFO_ENVIRONMENT = "${var.environment}"
        DEPLOYMENTINFO_SHARD = "${var.shard}"
        DEPLOYMENTINFO_REGION = "${var.octo_region}"
        DEPLOYMENTINFO_USERREGION = "<!--# echo var=\"user_region\" default=\"\" -->"
        ENABLE_SIMULCAST = "true"
        WEBSOCKET_KEEPALIVE_URL = "https://${var.domain}/_unlock"
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

# IP address of the Docker host
# See the "Running behind NAT or on a LAN environment" section in the Handbook:
# https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker#running-behind-nat-or-on-a-lan-environment
#DOCKER_HOST_ADDRESS=192.168.1.1

# Control whether the lobby feature should be enabled or not
#ENABLE_LOBBY=1

# Control whether the A/V moderation should be enabled or not
#ENABLE_AV_MODERATION=1

# Show a prejoin page before entering a conference
#ENABLE_PREJOIN_PAGE=0

# Enable the welcome page
#ENABLE_WELCOME_PAGE=1

# Enable the close page
#ENABLE_CLOSE_PAGE=0

# Disable measuring of audio levels
#DISABLE_AUDIO_LEVELS=0

# Enable noisy mic detection
#ENABLE_NOISY_MIC_DETECTION=1

# Enable breakout rooms
#ENABLE_BREAKOUT_ROOMS=1

#
# Let's Encrypt configuration
#

# Enable Let's Encrypt certificate generation
#ENABLE_LETSENCRYPT=1

# Domain for which to generate the certificate
#LETSENCRYPT_DOMAIN=meet.example.com

# E-Mail for receiving important account notifications (mandatory)
#LETSENCRYPT_EMAIL=alice@atlanta.net

# Use the staging server (for avoiding rate limits while testing)
#LETSENCRYPT_USE_STAGING=1


#
# Etherpad integration (for document sharing)
#

# Set etherpad-lite URL in docker local network (uncomment to enable)
#ETHERPAD_URL_BASE=http://etherpad.meet.jitsi:9001

# Set etherpad-lite public URL, including /p/ pad path fragment (uncomment to enable)
#ETHERPAD_PUBLIC_URL=https://etherpad.my.domain/p/

# Name your etherpad instance!
ETHERPAD_TITLE=Video Chat

# The default text of a pad
ETHERPAD_DEFAULT_PAD_TEXT="Welcome to Web Chat!\n\n"

# Name of the skin for etherpad
ETHERPAD_SKIN_NAME=colibris

# Skin variants for etherpad
ETHERPAD_SKIN_VARIANTS="super-light-toolbar super-light-editor light-background full-width-editor"


#
# Basic Jigasi configuration options (needed for SIP gateway support)
#

# SIP URI for incoming / outgoing calls
#JIGASI_SIP_URI=test@sip2sip.info

# Password for the specified SIP account as a clear text
#JIGASI_SIP_PASSWORD=passw0rd

# SIP server (use the SIP account domain if in doubt)
#JIGASI_SIP_SERVER=sip2sip.info

# SIP server port
#JIGASI_SIP_PORT=5060

# SIP server transport
#JIGASI_SIP_TRANSPORT=UDP

#
# Authentication configuration (see handbook for details)
#

# Enable authentication
#ENABLE_AUTH=1

# Enable guest access
#ENABLE_GUESTS=1

# Select authentication type: internal, jwt, ldap or matrix
#AUTH_TYPE=internal

# JWT authentication
#

# Application identifier
#JWT_APP_ID=my_jitsi_app_id

# Application secret known only to your token generator
#JWT_APP_SECRET=my_jitsi_app_secret

# (Optional) Set asap_accepted_issuers as a comma separated list
#JWT_ACCEPTED_ISSUERS=my_web_client,my_app_client

# (Optional) Set asap_accepted_audiences as a comma separated list
#JWT_ACCEPTED_AUDIENCES=my_server1,my_server2


# LDAP authentication (for more information see the Cyrus SASL saslauthd.conf man page)
#

# LDAP url for connection
#LDAP_URL=ldaps://ldap.domain.com/

# LDAP base DN. Can be empty
#LDAP_BASE=DC=example,DC=domain,DC=com

# LDAP user DN. Do not specify this parameter for the anonymous bind
#LDAP_BINDDN=CN=binduser,OU=users,DC=example,DC=domain,DC=com

# LDAP user password. Do not specify this parameter for the anonymous bind
#LDAP_BINDPW=LdapUserPassw0rd

# LDAP filter. Tokens example:
# %1-9 - if the input key is user@mail.domain.com, then %1 is com, %2 is domain and %3 is mail
# %s - %s is replaced by the complete service string
# %r - %r is replaced by the complete realm string
#LDAP_FILTER=(sAMAccountName=%u)

# LDAP authentication method
#LDAP_AUTH_METHOD=bind

# LDAP version
#LDAP_VERSION=3

# LDAP TLS using
#LDAP_USE_TLS=1

# List of SSL/TLS ciphers to allow
#LDAP_TLS_CIPHERS=SECURE256:SECURE128:!AES-128-CBC:!ARCFOUR-128:!CAMELLIA-128-CBC:!3DES-CBC:!CAMELLIA-128-CBC

# Require and verify server certificate
#LDAP_TLS_CHECK_PEER=1

# Path to CA cert file. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Path to CA certs directory. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_DIR=/etc/ssl/certs

# Wether to use starttls, implies LDAPv3 and requires ldap:// instead of ldaps://
# LDAP_START_TLS=1


# Matrix authentication (for more information see the documention of the "Prosody Auth Matrix User Verification" at https://github.com/matrix-org/prosody-mod-auth-matrix-user-verification)
#

# Base URL to the matrix user verification service (without ending slash)
#MATRIX_UVS_URL=https://uvs.example.com:3000

# (optional) The issuer of the auth token to be passed through. Must match what is being set as `iss` in the JWT. Defaut value is "issuer".
#MATRIX_UVS_ISSUER=issuer

# (optional) user verification service auth token, if authentication enabled
#MATRIX_UVS_AUTH_TOKEN=changeme

# (optional) Make Matrix room moderators owners of the Prosody room.
#MATRIX_UVS_SYNC_POWER_LEVELS=1


#
# Advanced configuration options (you generally don't need to change these)
#

# Internal XMPP server
XMPP_SERVER={{ env "NOMAD_IP_prosody_client" }}
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}

# Custom Prosody modules for XMPP_DOMAIN (comma separated)
XMPP_MODULES=

# Custom Prosody modules for MUC component (comma separated)
XMPP_MUC_MODULES=

# Custom Prosody modules for internal MUC component (comma separated)
XMPP_INTERNAL_MUC_MODULES=

# MUC for the JVB pool
JVB_BREWERY_MUC=jvbbrewery

# XMPP user for JVB client connections
JVB_AUTH_USER=jvb

# STUN servers used to discover the server's public IP
JVB_STUN_SERVERS=meet-jit-si-turnrelay.jitsi.net:443

# Media port for the Jitsi Videobridge
JVB_PORT={{ env "NOMAD_HOST_PORT_jvb_media" }}

# XMPP user for Jicofo client connections.
# NOTE: this option doesn't currently work due to a bug
JICOFO_AUTH_USER=focus

# Base URL of Jicofo's reservation REST API
#JICOFO_RESERVATION_REST_BASE_URL=http://reservation.example.com

# Enable Jicofo's health check REST API (http://<jicofo_base_url>:8888/about/health)
#JICOFO_ENABLE_HEALTH_CHECKS=true

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# Minimum port for media used by Jigasi
JIGASI_PORT_MIN=20000

# Maximum port for media used by Jigasi
JIGASI_PORT_MAX=20050

# Enable SDES srtp
#JIGASI_ENABLE_SDES_SRTP=1

# Keepalive method
#JIGASI_SIP_KEEP_ALIVE_METHOD=OPTIONS

# Health-check extension
#JIGASI_HEALTH_CHECK_SIP_URI=keepalive

# Health-check interval
#JIGASI_HEALTH_CHECK_INTERVAL=300000
#
# Enable Jigasi transcription
#ENABLE_TRANSCRIPTIONS=1

# Jigasi will record audio when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_RECORD_AUDIO=true

# Jigasi will send transcribed text to the chat when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_SEND_TXT=true

# Jigasi will post an url to the chat with transcription file [default: false]
#JIGASI_TRANSCRIBER_ADVERTISE_URL=true

# Credentials for connect to Cloud Google API from Jigasi
# Please read https://cloud.google.com/text-to-speech/docs/quickstart-protocol
# section "Before you begin" paragraph 1 to 5
# Copy the values from the json to the related env vars
#GC_PROJECT_ID=
#GC_PRIVATE_KEY_ID=
#GC_PRIVATE_KEY=
#GC_CLIENT_EMAIL=
#GC_CLIENT_ID=
#GC_CLIENT_CERT_URL=

# Enable recording
#ENABLE_RECORDING=1

# XMPP domain for the jibri recorder

# XMPP recorder user for Jibri client connections
JIBRI_RECORDER_USER=recorder

# Directory for recordings inside Jibri container
JIBRI_RECORDING_DIR=/config/recordings

# The finalizing script. Will run after recording is complete
#JIBRI_FINALIZE_RECORDING_SCRIPT_PATH=/config/finalize.sh

# XMPP user for Jibri client connections
JIBRI_XMPP_USER=jibri

# MUC name for the Jibri pool
JIBRI_BREWERY_MUC=jibribrewery

# MUC connection timeout
JIBRI_PENDING_TIMEOUT=90

# When jibri gets a request to start a service for a room, the room
# jid will look like: roomName@optional.prefixes.subdomain.xmpp_domain
# We'll build the url for the call by transforming that into:
# https://xmpp_domain/subdomain/roomName
# So if there are any prefixes in the jid (like jitsi meet, which
# has its participants join a muc at conference.xmpp_domain) then
# list that prefix here so it can be stripped out to generate
# the call url correctly
JIBRI_STRIP_DOMAIN_JID=conference

# Directory for logs inside Jibri container
JIBRI_LOGS_DIR=/config/logs

# Configure an external TURN server
# TURN_CREDENTIALS=secret
# TURN_HOST=turnserver.example.com
# TURN_PORT=443
# TURNS_HOST=turnserver.example.com
# TURNS_PORT=443

# Disable HTTPS: handle TLS connections outside of this setup
#DISABLE_HTTPS=1

# Enable FLoC
# Opt-In to Federated Learning of Cohorts tracking
#ENABLE_FLOC=0

# Redirect HTTP traffic to HTTPS
# Necessary for Let's Encrypt, relies on standard HTTPS port (443)
#ENABLE_HTTP_REDIRECT=1

# Send a `strict-transport-security` header to force browsers to use
# a secure and trusted connection. Recommended for production use.
# Defaults to 1 (send the header).
# ENABLE_HSTS=1

# Enable IPv6
# Provides means to disable IPv6 in environments that don't support it (get with the times, people!)
#ENABLE_IPV6=1

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

# Authenticate using external service or just focus external auth window if there is one already.
# TOKEN_AUTH_URL=https://auth.meet.example.com/{room}

# Sentry Error Tracking
# Sentry Data Source Name (Endpoint for Sentry project)
# Example: https://public:private@host:port/1
#JVB_SENTRY_DSN=
#JICOFO_SENTRY_DSN=
#JIGASI_SENTRY_DSN=

# Optional environment info to filter events
#SENTRY_ENVIRONMENT=production

# Optional release info to filter events
#SENTRY_RELEASE=1.0.0

# Optional properties for shutdown api
#COLIBRI_REST_ENABLED=true
#SHUTDOWN_REST_ENABLED=true

# Configure toolbar buttons. Add the buttons name separated with comma(no spaces between comma)
#TOOLBAR_BUTTONS=

# Hide the buttons at pre-join screen. Add the buttons name separated with comma
#HIDE_PREMEETING_BUTTONS=

# overrides

ENABLE_LETSENCRYPT=0
ENABLE_XMPP_WEBSOCKET=1
DISABLE_HTTPS=1
COLIBRI_WEBSOCKET_PORT={{ env "NOMAD_HOST_PORT_jvb_http_public" }}
EOF

        destination = "local/web.env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "prosody" {
      driver = "docker"

      config {
        image        = "jitsi/prosody:${var.prosody_tag}"
        ports = ["prosody-http","prosody-client"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom"]
      }

      env {
        ENABLE_RECORDING="1"
        ENABLE_OCTO="1"
        ENABLE_JVB_XMPP_SERVER="1"
        ENABLE_LOBBY="1"
        ENABLE_AV_MODERATION="1"
        ENABLE_BREAKOUT_ROOMS="1"
        ENABLE_AUTH="1"
        AUTH_TYPE="jwt"
        JWT_ALLOW_EMPTY="1"
        JWT_ACCEPTED_ISSUERS="${var.jwt_accepted_issuers}"
        JWT_ACCEPTED_AUDIENCES="${var.jwt_accepted_audiences}"
        JWT_ASAP_KEYSERVER="${var.jwt_asap_keyserver}"
        JWT_APP_ID="jitsi"
        TURN_CREDENTIALS="${var.turnrelay_password}"
        TURNS_HOST="${var.turnrelay_host}"
        TURN_HOST="${var.turnrelay_host}"
        MAX_PARTICIPANTS=500
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JICOFO_AUTH_PASSWORD = "${var.jicofo_auth_password}"
        JVB_AUTH_PASSWORD = "${var.jvb_auth_password}"
        JIGASI_XMPP_PASSWORD = "${var.jigasi_xmpp_password}"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.${var.domain}"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.${var.domain}"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_measure_stanza_counts/mod_measure_stanza_counts.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_debug_traceback/mod_debug_traceback.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_secure_interfaces/mod_secure_interfaces.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/mod_firewall.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/definitions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/actions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/marks.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/conditions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/test.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_log_ringbuffer/mod_log_ringbuffer.lua"
        destination = "local/prosody-plugins-custom"
      }


      template {
        data = <<EOF
#
# Basic configuration options
#
GLOBAL_CONFIG="statistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\n"
GLOBAL_MODULES="http_openmetrics,measure_stanza_counts,log_ringbuffer,firewall,muc_census,log_ringbuffer,external_services"
XMPP_MODULES=
XMPP_INTERNAL_MUC_MODULES=
XMPP_MUC_MODULES="{{ if eq "${var.enable_muc_allowners}" "true" }}muc_allowners{{ end }}"
XMPP_SERVER={{ env "NOMAD_IP_prosody_client" }}
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}
CONFIG=~/.jitsi-meet-cfg
TZ=UTC
ENABLE_LETSENCRYPT=0
ENABLE_XMPP_WEBSOCKET=1
DISABLE_HTTPS=1

# MUC for the JVB pool
JVB_BREWERY_MUC=jvbbrewery

# XMPP user for JVB client connections
JVB_AUTH_USER=jvb

# XMPP user for Jicofo client connections.
# NOTE: this option doesn't currently work due to a bug
JICOFO_AUTH_USER=focus

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# XMPP recorder user for Jibri client connections
JIBRI_RECORDER_USER=recorder

# Directory for recordings inside Jibri container
JIBRI_RECORDING_DIR=/config/recordings

# The finalizing script. Will run after recording is complete
#JIBRI_FINALIZE_RECORDING_SCRIPT_PATH=/config/finalize.sh

# XMPP user for Jibri client connections
JIBRI_XMPP_USER=jibri

# MUC name for the Jibri pool
JIBRI_BREWERY_MUC=jibribrewery

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

EOF

        destination = "local/prosody.env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "prosody-jvb" {
      driver = "docker"

      config {
        image        = "jitsi/prosody:${var.prosody_tag}"
        ports = ["prosody-jvb-client","prosody-jvb-http"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom"]
      }

      env {
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JICOFO_AUTH_PASSWORD = "${var.jicofo_auth_password}"
        JVB_AUTH_PASSWORD = "${var.jvb_auth_password}"
        JIGASI_XMPP_PASSWORD = "${var.jigasi_xmpp_password}"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.jvb.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_measure_stanza_counts/mod_measure_stanza_counts.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_debug_traceback/mod_debug_traceback.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_secure_interfaces/mod_secure_interfaces.lua"
        destination = "local/prosody-plugins-custom"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/mod_firewall.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/definitions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/actions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/marks.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/conditions.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_firewall/test.lib.lua"
        destination = "local/prosody-plugins-custom/mod_firewall"
      }
      artifact {
        source      = "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_log_ringbuffer/mod_log_ringbuffer.lua"
        destination = "local/prosody-plugins-custom"
      }

      template {
        data = <<EOF
#
# Basic configuration options
#
GLOBAL_CONFIG="statistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\""
GLOBAL_MODULES="http_openmetrics,measure_stanza_counts,log_ringbuffer,firewall,log_ringbuffer"

FOO=bar2
# Directory where all configuration will be stored
CONFIG=~/.jitsi-meet-cfg

# Exposed HTTP port
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}

# Exposed HTTPS port
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}

# System time zone
TZ=UTC

# IP address of the Docker host
# See the "Running behind NAT or on a LAN environment" section in the Handbook:
# https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker#running-behind-nat-or-on-a-lan-environment
#DOCKER_HOST_ADDRESS=192.168.1.1

# Control whether the lobby feature should be enabled or not
#ENABLE_LOBBY=1

# Control whether the A/V moderation should be enabled or not
#ENABLE_AV_MODERATION=1

# Show a prejoin page before entering a conference
#ENABLE_PREJOIN_PAGE=0

# Enable the welcome page
#ENABLE_WELCOME_PAGE=1

# Enable the close page
#ENABLE_CLOSE_PAGE=0

# Disable measuring of audio levels
#DISABLE_AUDIO_LEVELS=0

# Enable noisy mic detection
#ENABLE_NOISY_MIC_DETECTION=1

# Enable breakout rooms
#ENABLE_BREAKOUT_ROOMS=1

#
# Let's Encrypt configuration
#

# Enable Let's Encrypt certificate generation
#ENABLE_LETSENCRYPT=1

# Domain for which to generate the certificate
#LETSENCRYPT_DOMAIN=meet.example.com

# E-Mail for receiving important account notifications (mandatory)
#LETSENCRYPT_EMAIL=alice@atlanta.net

# Use the staging server (for avoiding rate limits while testing)
#LETSENCRYPT_USE_STAGING=1


#
# Etherpad integration (for document sharing)
#

# Set etherpad-lite URL in docker local network (uncomment to enable)
#ETHERPAD_URL_BASE=http://etherpad.meet.jitsi:9001

# Set etherpad-lite public URL, including /p/ pad path fragment (uncomment to enable)
#ETHERPAD_PUBLIC_URL=https://etherpad.my.domain/p/

# Name your etherpad instance!
ETHERPAD_TITLE=Video Chat

# The default text of a pad
ETHERPAD_DEFAULT_PAD_TEXT="Welcome to Web Chat!\n\n"

# Name of the skin for etherpad
ETHERPAD_SKIN_NAME=colibris

# Skin variants for etherpad
ETHERPAD_SKIN_VARIANTS="super-light-toolbar super-light-editor light-background full-width-editor"


#
# Basic Jigasi configuration options (needed for SIP gateway support)
#

# SIP URI for incoming / outgoing calls
#JIGASI_SIP_URI=test@sip2sip.info

# Password for the specified SIP account as a clear text
#JIGASI_SIP_PASSWORD=passw0rd

# SIP server (use the SIP account domain if in doubt)
#JIGASI_SIP_SERVER=sip2sip.info

# SIP server port
#JIGASI_SIP_PORT=5060

# SIP server transport
#JIGASI_SIP_TRANSPORT=UDP

#
# Authentication configuration (see handbook for details)
#

# Enable authentication
#ENABLE_AUTH=1

# Enable guest access
#ENABLE_GUESTS=1

# Select authentication type: internal, jwt, ldap or matrix
#AUTH_TYPE=internal

# JWT authentication
#

# Application identifier
#JWT_APP_ID=my_jitsi_app_id

# Application secret known only to your token generator
#JWT_APP_SECRET=my_jitsi_app_secret

# (Optional) Set asap_accepted_issuers as a comma separated list
#JWT_ACCEPTED_ISSUERS=my_web_client,my_app_client

# (Optional) Set asap_accepted_audiences as a comma separated list
#JWT_ACCEPTED_AUDIENCES=my_server1,my_server2


# LDAP authentication (for more information see the Cyrus SASL saslauthd.conf man page)
#

# LDAP url for connection
#LDAP_URL=ldaps://ldap.domain.com/

# LDAP base DN. Can be empty
#LDAP_BASE=DC=example,DC=domain,DC=com

# LDAP user DN. Do not specify this parameter for the anonymous bind
#LDAP_BINDDN=CN=binduser,OU=users,DC=example,DC=domain,DC=com

# LDAP user password. Do not specify this parameter for the anonymous bind
#LDAP_BINDPW=LdapUserPassw0rd

# LDAP filter. Tokens example:
# %1-9 - if the input key is user@mail.domain.com, then %1 is com, %2 is domain and %3 is mail
# %s - %s is replaced by the complete service string
# %r - %r is replaced by the complete realm string
#LDAP_FILTER=(sAMAccountName=%u)

# LDAP authentication method
#LDAP_AUTH_METHOD=bind

# LDAP version
#LDAP_VERSION=3

# LDAP TLS using
#LDAP_USE_TLS=1

# List of SSL/TLS ciphers to allow
#LDAP_TLS_CIPHERS=SECURE256:SECURE128:!AES-128-CBC:!ARCFOUR-128:!CAMELLIA-128-CBC:!3DES-CBC:!CAMELLIA-128-CBC

# Require and verify server certificate
#LDAP_TLS_CHECK_PEER=1

# Path to CA cert file. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Path to CA certs directory. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_DIR=/etc/ssl/certs

# Wether to use starttls, implies LDAPv3 and requires ldap:// instead of ldaps://
# LDAP_START_TLS=1


# Matrix authentication (for more information see the documention of the "Prosody Auth Matrix User Verification" at https://github.com/matrix-org/prosody-mod-auth-matrix-user-verification)
#

# Base URL to the matrix user verification service (without ending slash)
#MATRIX_UVS_URL=https://uvs.example.com:3000

# (optional) The issuer of the auth token to be passed through. Must match what is being set as `iss` in the JWT. Defaut value is "issuer".
#MATRIX_UVS_ISSUER=issuer

# (optional) user verification service auth token, if authentication enabled
#MATRIX_UVS_AUTH_TOKEN=changeme

# (optional) Make Matrix room moderators owners of the Prosody room.
#MATRIX_UVS_SYNC_POWER_LEVELS=1


#
# Advanced configuration options (you generally don't need to change these)
#

# Internal XMPP domain

# Internal XMPP server
XMPP_SERVER={{ env "NOMAD_IP_prosody_jvb_client" }}
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_jvb_client" }}

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_jvb_http" }}:{{ env "NOMAD_HOST_PORT_prosody_jvb_http" }}

# Custom Prosody modules for XMPP_DOMAIN (comma separated)
XMPP_MODULES=

# Custom Prosody modules for MUC component (comma separated)
XMPP_MUC_MODULES=

# Custom Prosody modules for internal MUC component (comma separated)
XMPP_INTERNAL_MUC_MODULES=

# MUC for the JVB pool
JVB_BREWERY_MUC=jvbbrewery

# XMPP user for JVB client connections
JVB_AUTH_USER=jvb

# STUN servers used to discover the server's public IP
JVB_STUN_SERVERS=meet-jit-si-turnrelay.jitsi.net:443

# Media port for the Jitsi Videobridge
JVB_PORT=10000

# XMPP user for Jicofo client connections.
# NOTE: this option doesn't currently work due to a bug
JICOFO_AUTH_USER=focus

# Base URL of Jicofo's reservation REST API
#JICOFO_RESERVATION_REST_BASE_URL=http://reservation.example.com

# Enable Jicofo's health check REST API (http://<jicofo_base_url>:8888/about/health)
#JICOFO_ENABLE_HEALTH_CHECKS=true

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# Minimum port for media used by Jigasi
JIGASI_PORT_MIN=20000

# Maximum port for media used by Jigasi
JIGASI_PORT_MAX=20050

# Enable SDES srtp
#JIGASI_ENABLE_SDES_SRTP=1

# Keepalive method
#JIGASI_SIP_KEEP_ALIVE_METHOD=OPTIONS

# Health-check extension
#JIGASI_HEALTH_CHECK_SIP_URI=keepalive

# Health-check interval
#JIGASI_HEALTH_CHECK_INTERVAL=300000
#
# Enable Jigasi transcription
#ENABLE_TRANSCRIPTIONS=1

# Jigasi will record audio when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_RECORD_AUDIO=true

# Jigasi will send transcribed text to the chat when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_SEND_TXT=true

# Jigasi will post an url to the chat with transcription file [default: false]
#JIGASI_TRANSCRIBER_ADVERTISE_URL=true

# Credentials for connect to Cloud Google API from Jigasi
# Please read https://cloud.google.com/text-to-speech/docs/quickstart-protocol
# section "Before you begin" paragraph 1 to 5
# Copy the values from the json to the related env vars
#GC_PROJECT_ID=
#GC_PRIVATE_KEY_ID=
#GC_PRIVATE_KEY=
#GC_CLIENT_EMAIL=
#GC_CLIENT_ID=
#GC_CLIENT_CERT_URL=

# Enable recording
#ENABLE_RECORDING=1

# XMPP recorder user for Jibri client connections
JIBRI_RECORDER_USER=recorder

# Directory for recordings inside Jibri container
JIBRI_RECORDING_DIR=/config/recordings

# The finalizing script. Will run after recording is complete
#JIBRI_FINALIZE_RECORDING_SCRIPT_PATH=/config/finalize.sh

# XMPP user for Jibri client connections
JIBRI_XMPP_USER=jibri

# MUC name for the Jibri pool
JIBRI_BREWERY_MUC=jibribrewery

# MUC connection timeout
JIBRI_PENDING_TIMEOUT=90

# When jibri gets a request to start a service for a room, the room
# jid will look like: roomName@optional.prefixes.subdomain.xmpp_domain
# We'll build the url for the call by transforming that into:
# https://xmpp_domain/subdomain/roomName
# So if there are any prefixes in the jid (like jitsi meet, which
# has its participants join a muc at conference.xmpp_domain) then
# list that prefix here so it can be stripped out to generate
# the call url correctly
JIBRI_STRIP_DOMAIN_JID=muc

# Directory for logs inside Jibri container
JIBRI_LOGS_DIR=/config/logs

# Configure an external TURN server
# TURN_CREDENTIALS=secret
# TURN_HOST=turnserver.example.com
# TURN_PORT=443
# TURNS_HOST=turnserver.example.com
# TURNS_PORT=443

# Disable HTTPS: handle TLS connections outside of this setup
#DISABLE_HTTPS=1

# Enable FLoC
# Opt-In to Federated Learning of Cohorts tracking
#ENABLE_FLOC=0

# Redirect HTTP traffic to HTTPS
# Necessary for Let's Encrypt, relies on standard HTTPS port (443)
#ENABLE_HTTP_REDIRECT=1

# Send a `strict-transport-security` header to force browsers to use
# a secure and trusted connection. Recommended for production use.
# Defaults to 1 (send the header).
# ENABLE_HSTS=1

# Enable IPv6
# Provides means to disable IPv6 in environments that don't support it (get with the times, people!)
#ENABLE_IPV6=1

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

# Authenticate using external service or just focus external auth window if there is one already.
# TOKEN_AUTH_URL=https://auth.meet.example.com/{room}

# Sentry Error Tracking
# Sentry Data Source Name (Endpoint for Sentry project)
# Example: https://public:private@host:port/1
#JVB_SENTRY_DSN=
#JICOFO_SENTRY_DSN=
#JIGASI_SENTRY_DSN=

# Optional environment info to filter events
#SENTRY_ENVIRONMENT=production

# Optional release info to filter events
#SENTRY_RELEASE=1.0.0

# Optional properties for shutdown api
#COLIBRI_REST_ENABLED=true
#SHUTDOWN_REST_ENABLED=true

# Configure toolbar buttons. Add the buttons name separated with comma(no spaces between comma)
#TOOLBAR_BUTTONS=

# Hide the buttons at pre-join screen. Add the buttons name separated with comma
#HIDE_PREMEETING_BUTTONS=

# overrides

ENABLE_LETSENCRYPT=0
ENABLE_XMPP_WEBSOCKET=1
DISABLE_HTTPS=1
EOF

        destination = "local/prosody-jvb.env"
        env = true
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "jicofo" {
      driver = "docker"

      config {
        image        = "jitsi/jicofo:${var.jicofo_tag}"
        ports = ["jicofo-http"]
      }

      env {
        ENABLE_RECORDING="1"
        ENABLE_OCTO="1"
        JICOFO_ENABLE_REST="1"
        AUTH_TYPE="jwt"
        JICOFO_ENABLE_BRIDGE_HEALTH_CHECKS="1"
        JICOFO_HEALTH_CHECKS_USE_PRESENCE="1"
        JIGASI_SIP_URI="sip.example.com"
        ENABLE_AUTO_OWNER="${var.enable_auto_owner}"
        OCTO_BRIDGE_SELECTION_STRATEGY="RegionBasedBridgeSelectionStrategy"
        // BRIDGE_STRESS_THRESHOLD=""
        BRIDGE_AVG_PARTICIPANT_STRESS="0.005"
        MAX_BRIDGE_PARTICIPANTS="80"
        ENABLE_JVB_XMPP_SERVER="1"
        ENABLE_CODEC_VP8="1"
        ENABLE_CODEC_VP9="1"
        ENABLE_CODEC_H264="1"
        ENABLE_CODEC_OPUS_RED="1"
        JICOFO_CONF_SSRC_REWRITING="0"
        JICOFO_CONF_MAX_AUDIO_SENDERS=999999
        JICOFO_CONF_MAX_VIDEO_SENDERS=999999
        JICOFO_CONF_STRIP_SIMULCAST="1"
        JICOFO_SOURCE_SIGNALING_DELAYS="{ 50: 1000, 100: 2000 }"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JICOFO_AUTH_PASSWORD = "${var.jicofo_auth_password}"
        JVB_AUTH_PASSWORD = "${var.jvb_auth_password}"
        JIGASI_XMPP_PASSWORD = "${var.jigasi_xmpp_password}"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.${var.domain}"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.${var.domain}"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
        JICOFO_OCTO_REGION = "${var.octo_region}"
        JICOFO_ENABLE_HEALTH_CHECKS="1"
      }

      template {
        data = <<EOF
#
# Basic configuration options
#
ENABLE_RECORDING="1"
ENABLE_OCTO="1"

JICOFO_OPTS="-Djicofo.xmpp.client.port={{ env "NOMAD_HOST_PORT_prosody_client" }}"

# Directory where all configuration will be stored
CONFIG=~/.jitsi-meet-cfg

# Exposed HTTP port
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}

# Exposed HTTPS port
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}

# System time zone
TZ=UTC

# IP address of the Docker host
# See the "Running behind NAT or on a LAN environment" section in the Handbook:
# https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker#running-behind-nat-or-on-a-lan-environment
#DOCKER_HOST_ADDRESS=192.168.1.1
# Control whether the lobby feature should be enabled or not
#ENABLE_LOBBY=1

# Control whether the A/V moderation should be enabled or not
#ENABLE_AV_MODERATION=1

# Show a prejoin page before entering a conference
#ENABLE_PREJOIN_PAGE=0

# Enable the welcome page
#ENABLE_WELCOME_PAGE=1

# Enable the close page
#ENABLE_CLOSE_PAGE=0

# Disable measuring of audio levels
#DISABLE_AUDIO_LEVELS=0

# Enable noisy mic detection
#ENABLE_NOISY_MIC_DETECTION=1

# Enable breakout rooms
#ENABLE_BREAKOUT_ROOMS=1

#
# Let's Encrypt configuration
#

# Enable Let's Encrypt certificate generation
#ENABLE_LETSENCRYPT=1

# Domain for which to generate the certificate
#LETSENCRYPT_DOMAIN=meet.example.com

# E-Mail for receiving important account notifications (mandatory)
#LETSENCRYPT_EMAIL=alice@atlanta.net

# Use the staging server (for avoiding rate limits while testing)
#LETSENCRYPT_USE_STAGING=1


#
# Etherpad integration (for document sharing)
#

# Set etherpad-lite URL in docker local network (uncomment to enable)
#ETHERPAD_URL_BASE=http://etherpad.meet.jitsi:9001

# Set etherpad-lite public URL, including /p/ pad path fragment (uncomment to enable)
#ETHERPAD_PUBLIC_URL=https://etherpad.my.domain/p/

# Name your etherpad instance!
ETHERPAD_TITLE=Video Chat

# The default text of a pad
ETHERPAD_DEFAULT_PAD_TEXT="Welcome to Web Chat!\n\n"

# Name of the skin for etherpad
ETHERPAD_SKIN_NAME=colibris

# Skin variants for etherpad
ETHERPAD_SKIN_VARIANTS="super-light-toolbar super-light-editor light-background full-width-editor"


#
# Basic Jigasi configuration options (needed for SIP gateway support)
#

# SIP URI for incoming / outgoing calls
#JIGASI_SIP_URI=test@sip2sip.info

# Password for the specified SIP account as a clear text
#JIGASI_SIP_PASSWORD=passw0rd

# SIP server (use the SIP account domain if in doubt)
#JIGASI_SIP_SERVER=sip2sip.info

# SIP server port
#JIGASI_SIP_PORT=5060

# SIP server transport
#JIGASI_SIP_TRANSPORT=UDP

#
# Authentication configuration (see handbook for details)
#

# Enable authentication
#ENABLE_AUTH=1

# Enable guest access
#ENABLE_GUESTS=1

# Select authentication type: internal, jwt, ldap or matrix
#AUTH_TYPE=internal

# JWT authentication
#

# Application identifier
#JWT_APP_ID=my_jitsi_app_id

# Application secret known only to your token generator
#JWT_APP_SECRET=my_jitsi_app_secret

# (Optional) Set asap_accepted_issuers as a comma separated list
#JWT_ACCEPTED_ISSUERS=my_web_client,my_app_client

# (Optional) Set asap_accepted_audiences as a comma separated list
#JWT_ACCEPTED_AUDIENCES=my_server1,my_server2


# LDAP authentication (for more information see the Cyrus SASL saslauthd.conf man page)
#

# LDAP url for connection
#LDAP_URL=ldaps://ldap.domain.com/

# LDAP base DN. Can be empty
#LDAP_BASE=DC=example,DC=domain,DC=com

# LDAP user DN. Do not specify this parameter for the anonymous bind
#LDAP_BINDDN=CN=binduser,OU=users,DC=example,DC=domain,DC=com

# LDAP user password. Do not specify this parameter for the anonymous bind
#LDAP_BINDPW=LdapUserPassw0rd

# LDAP filter. Tokens example:
# %1-9 - if the input key is user@mail.domain.com, then %1 is com, %2 is domain and %3 is mail
# %s - %s is replaced by the complete service string
# %r - %r is replaced by the complete realm string
#LDAP_FILTER=(sAMAccountName=%u)

# LDAP authentication method
#LDAP_AUTH_METHOD=bind

# LDAP version
#LDAP_VERSION=3

# LDAP TLS using
#LDAP_USE_TLS=1

# List of SSL/TLS ciphers to allow
#LDAP_TLS_CIPHERS=SECURE256:SECURE128:!AES-128-CBC:!ARCFOUR-128:!CAMELLIA-128-CBC:!3DES-CBC:!CAMELLIA-128-CBC

# Require and verify server certificate
#LDAP_TLS_CHECK_PEER=1

# Path to CA cert file. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Path to CA certs directory. Used when server certificate verify is enabled
#LDAP_TLS_CACERT_DIR=/etc/ssl/certs

# Wether to use starttls, implies LDAPv3 and requires ldap:// instead of ldaps://
# LDAP_START_TLS=1


# Matrix authentication (for more information see the documention of the "Prosody Auth Matrix User Verification" at https://github.com/matrix-org/prosody-mod-auth-matrix-user-verification)
#

# Base URL to the matrix user verification service (without ending slash)
#MATRIX_UVS_URL=https://uvs.example.com:3000

# (optional) The issuer of the auth token to be passed through. Must match what is being set as `iss` in the JWT. Defaut value is "issuer".
#MATRIX_UVS_ISSUER=issuer

# (optional) user verification service auth token, if authentication enabled
#MATRIX_UVS_AUTH_TOKEN=changeme

# (optional) Make Matrix room moderators owners of the Prosody room.
#MATRIX_UVS_SYNC_POWER_LEVELS=1


#
# Advanced configuration options (you generally don't need to change these)
#

# Internal XMPP server
XMPP_SERVER={{ env "NOMAD_IP_prosody_client" }}
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}

# Custom Prosody modules for XMPP_DOMAIN (comma separated)
XMPP_MODULES=

# Custom Prosody modules for MUC component (comma separated)
XMPP_MUC_MODULES=

# Custom Prosody modules for internal MUC component (comma separated)
XMPP_INTERNAL_MUC_MODULES=

# MUC for the JVB pool
JVB_BREWERY_MUC=jvbbrewery

# XMPP user for JVB client connections
JVB_AUTH_USER=jvb

# STUN servers used to discover the server's public IP
JVB_STUN_SERVERS=meet-jit-si-turnrelay.jitsi.net:443

# Media port for the Jitsi Videobridge
JVB_PORT=10000

# XMPP user for Jicofo client connections.
# NOTE: this option doesn't currently work due to a bug
JICOFO_AUTH_USER=focus

# Base URL of Jicofo's reservation REST API
#JICOFO_RESERVATION_REST_BASE_URL=http://reservation.example.com

# Enable Jicofo's health check REST API (http://<jicofo_base_url>:8888/about/health)
#JICOFO_ENABLE_HEALTH_CHECKS=true

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# Minimum port for media used by Jigasi
JIGASI_PORT_MIN=20000

# Maximum port for media used by Jigasi
JIGASI_PORT_MAX=20050

# Enable SDES srtp
#JIGASI_ENABLE_SDES_SRTP=1

# Keepalive method
#JIGASI_SIP_KEEP_ALIVE_METHOD=OPTIONS

# Health-check extension
#JIGASI_HEALTH_CHECK_SIP_URI=keepalive

# Health-check interval
#JIGASI_HEALTH_CHECK_INTERVAL=300000
#
# Enable Jigasi transcription
#ENABLE_TRANSCRIPTIONS=1

# Jigasi will record audio when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_RECORD_AUDIO=true

# Jigasi will send transcribed text to the chat when transcriber is on [default: false]
#JIGASI_TRANSCRIBER_SEND_TXT=true

# Jigasi will post an url to the chat with transcription file [default: false]
#JIGASI_TRANSCRIBER_ADVERTISE_URL=true

# Credentials for connect to Cloud Google API from Jigasi
# Please read https://cloud.google.com/text-to-speech/docs/quickstart-protocol
# section "Before you begin" paragraph 1 to 5
# Copy the values from the json to the related env vars
#GC_PROJECT_ID=
#GC_PRIVATE_KEY_ID=
#GC_PRIVATE_KEY=
#GC_CLIENT_EMAIL=
#GC_CLIENT_ID=
#GC_CLIENT_CERT_URL=

# Enable recording
#ENABLE_RECORDING=1

# XMPP recorder user for Jibri client connections
JIBRI_RECORDER_USER=recorder

# Directory for recordings inside Jibri container
JIBRI_RECORDING_DIR=/config/recordings

# The finalizing script. Will run after recording is complete
#JIBRI_FINALIZE_RECORDING_SCRIPT_PATH=/config/finalize.sh

# XMPP user for Jibri client connections
JIBRI_XMPP_USER=jibri

# MUC name for the Jibri pool
JIBRI_BREWERY_MUC=jibribrewery

# MUC connection timeout
JIBRI_PENDING_TIMEOUT=90

# When jibri gets a request to start a service for a room, the room
# jid will look like: roomName@optional.prefixes.subdomain.xmpp_domain
# We'll build the url for the call by transforming that into:
# https://xmpp_domain/subdomain/roomName
# So if there are any prefixes in the jid (like jitsi meet, which
# has its participants join a muc at conference.xmpp_domain) then
# list that prefix here so it can be stripped out to generate
# the call url correctly
JIBRI_STRIP_DOMAIN_JID=muc

# Directory for logs inside Jibri container
JIBRI_LOGS_DIR=/config/logs

# Configure an external TURN server
# TURN_CREDENTIALS=secret
# TURN_HOST=turnserver.example.com
# TURN_PORT=443
# TURNS_HOST=turnserver.example.com
# TURNS_PORT=443

# Disable HTTPS: handle TLS connections outside of this setup
#DISABLE_HTTPS=1

# Enable FLoC
# Opt-In to Federated Learning of Cohorts tracking
#ENABLE_FLOC=0

# Redirect HTTP traffic to HTTPS
# Necessary for Let's Encrypt, relies on standard HTTPS port (443)
#ENABLE_HTTP_REDIRECT=1

# Send a `strict-transport-security` header to force browsers to use
# a secure and trusted connection. Recommended for production use.
# Defaults to 1 (send the header).
# ENABLE_HSTS=1

# Enable IPv6
# Provides means to disable IPv6 in environments that don't support it (get with the times, people!)
#ENABLE_IPV6=1

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

# Authenticate using external service or just focus external auth window if there is one already.
# TOKEN_AUTH_URL=https://auth.meet.example.com/{room}

# Sentry Error Tracking
# Sentry Data Source Name (Endpoint for Sentry project)
# Example: https://public:private@host:port/1
#JVB_SENTRY_DSN=
#JICOFO_SENTRY_DSN=
#JIGASI_SENTRY_DSN=

# Optional environment info to filter events
#SENTRY_ENVIRONMENT=production

# Optional release info to filter events
#SENTRY_RELEASE=1.0.0

# Optional properties for shutdown api
#COLIBRI_REST_ENABLED=true
#SHUTDOWN_REST_ENABLED=true

# Configure toolbar buttons. Add the buttons name separated with comma(no spaces between comma)
#TOOLBAR_BUTTONS=

# Hide the buttons at pre-join screen. Add the buttons name separated with comma
#HIDE_PREMEETING_BUTTONS=

# overrides

ENABLE_LETSENCRYPT=0
ENABLE_XMPP_WEBSOCKET=1
ENABLE_JVB_XMPP_SERVER=1
JVB_XMPP_SERVER={{ env "NOMAD_IP_prosody_jvb_client" }}
JVB_XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_jvb_client" }}
DISABLE_HTTPS=1
JICOFO_BRIDGE_REGION_GROUPS="[\"eu-central-1\", \"eu-west-1\", \"eu-west-2\", \"eu-west-3\", \"uk-london-1\", \"eu-amsterdam-1\", \"eu-frankfurt-1\"],[\"us-east-1\", \"us-west-2\", \"us-ashburn-1\", \"us-phoenix-1\"],[\"ap-mumbai-1\", \"ap-tokyo-1\", \"ap-south-1\", \"ap-northeast-1\"],[\"ap-sydney-1\", \"ap-southeast-2\"],[\"ca-toronto-1\", \"ca-central-1\"],[\"me-jeddah-1\", \"me-south-1\"],[\"sa-saopaulo-1\", \"sa-east-1\"]"

EOF

        destination = "local/jicofo.env"
        env = true
      }

      resources {
        cpu    = 1000
        memory = 4096
      }
    }


  }
}