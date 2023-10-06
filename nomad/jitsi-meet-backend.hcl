variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "jicofo_tag" {
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

variable "shard_id" {
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

variable jwt_allow_empty {
    type = string
    default = "false"
}

variable asap_disable_require_room_claim {
    type = string
    default = "false"
}

variable prosody_cache_keys_url {
    type = string
    default = ""
}

variable turnrelay_host {
  type = string
  default = "turn.example.com"
}

variable turnrelay_password {
  type = string
  default = "password"
}

variable branding_name {
  type = string
  default = "jitsi-meet"
}

variable visitors_enabled {
  type = string
  default = "false"
}

variable visitors_count {
    type = number
    default = 0
}

variable signal_api_domain_name {
    type = string
    default = "signal-api.example.com"
}

variable wait_for_host_enabled {
    type = string
    default = "false"
}

variable password_waiting_for_host_enabled {
    type = string
    default = "false"
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

  group "vnodes" {
    count = var.visitors_count

    update {
      max_parallel = var.visitors_count
      health_check      = "checks"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    network {
      port "prosody-http" {
        to = 5280
      }
      port "prosody-client" {
      }
      port "prosody-s2s" {
        to = 5269
      }
    }

    service {
      name = "prosody-vnode"
      tags = ["${var.shard}","v-${NOMAD_ALLOC_INDEX}","ip-${attr.unique.network.ip-address}"]
      port = "prosody-http"
      meta {
        domain = "${var.domain}"
        shard = "${var.shard}"
        release_number = "${var.release_number}"
        prosody_client_port = "${NOMAD_HOST_PORT_prosody_client}"
        prosody_s2s_port = "${NOMAD_HOST_PORT_prosody_s2s}"
        environment = "${meta.environment}"
        vindex = "${NOMAD_ALLOC_INDEX}"
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

    task "prosody" {
      driver = "docker"

      config {
        image        = "jitsi/prosody:${var.prosody_tag}"
        ports = ["prosody-http","prosody-client","prosody-s2s"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom"]
      }

      env {
        PROSODY_MODE="visitors"
        VISITORS_MAX_PARTICIPANTS=5
        VISITORS_MAX_VISITORS_PER_NODE=250
        PROSODY_VISITORS_MUC_PREFIX="conference"
        ENABLE_VISITORS="${var.visitors_enabled}"
        PROSODY_VISITOR_INDEX="${NOMAD_ALLOC_INDEX}"
        PROSODY_ENABLE_RATE_LIMITS="1"
        PROSODY_RATE_LIMIT_ALLOW_RANGES="10.0.0.0/8,172.17.0.0/16"
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
{{ range service "shard-${var.shard}.signal" -}}
    {{ scratch.SetX "xmpp_server" . -}}
{{ end -}}

#
# prosody vnode configuration options
#

{{ with scratch.Get "xmpp_server"  }}
XMPP_SERVER={{ .ServiceMeta.prosody_client_ip }}
XMPP_SERVER_S2S_PORT={{ .ServiceMeta.prosody_s2s_port }}
{{ end -}}
GLOBAL_CONFIG="statistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\n"
GLOBAL_MODULES="http_openmetrics,measure_stanza_counts,log_ringbuffer,firewall,muc_census,secure_interfaces,external_services,turncredentials_http"
XMPP_MODULES="jiconop"
XMPP_INTERNAL_MUC_MODULES=
XMPP_MUC_MODULES=
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}

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
      port "nginx-status" {
        to = 888
      }
      port "prosody-http" {
        to = 5280
      }
      port "prosody-s2s" {
        to = 5269
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
        prosody_s2s_port = "${NOMAD_HOST_PORT_prosody_s2s}"
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

    task "prosody" {
      driver = "docker"

      config {
        image        = "jitsi/prosody:${var.prosody_tag}"
        ports = ["prosody-http","prosody-client","prosody-s2s"]
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
        ENABLE_VISITORS="${var.visitors_enabled}"
        PROSODY_VISITORS_MUC_PREFIX="conference"
        PROSODY_ENABLE_RATE_LIMITS="1"
        AUTH_TYPE="jwt"
        JWT_ALLOW_EMPTY="${var.jwt_allow_empty}"
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
{{ range service "${var.shard}.prosody-vnode" -}}
    {{ scratch.MapSetX "vnodes" .ServiceMeta.vindex . -}}
{{ end -}}

VISITORS_XMPP_SERVER={{ range $i, $e := scratch.MapValues "vnodes" }}{{ if gt $i 0 }},{{ end }}{{ $e.Address }}:{{ $e.ServiceMeta.prosody_s2s_port}}{{ end }}
#
# prosody main configuration options
#
GLOBAL_CONFIG="statistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\n
{{- if eq "${var.asap_disable_require_room_claim}" "true" -}}
asap_require_room_claim = false;\n
{{- end -}}
{{- if eq "${var.password_waiting_for_host_enabled}" "true" -}}
enable_password_waiting_for_host = true;\n
{{- end -}}
"
GLOBAL_MODULES="http_openmetrics,measure_stanza_counts,log_ringbuffer,firewall,muc_census,muc_end_meeting,secure_interfaces,external_services,turncredentials_http"
XMPP_MODULES=persistent_lobby
XMPP_INTERNAL_MUC_MODULES=
# hack to avoid token_verification when firebase auth is on
JWT_TOKEN_AUTH_MODULE=muc_allowners
XMPP_CONFIGURATION="cache_keys_url=\"${var.prosody_cache_keys_url}\",shard_name=\"${var.shard}\",region_name=\"{{ env "meta.cloud_region" }}\",release_number=\"${var.release_number}\""
XMPP_MUC_CONFIGURATION="muc_room_allow_persistent = false"
XMPP_MUC_MODULES="{{ if eq "${var.enable_muc_allowners}" "true" }}muc_allowners,{{ end }}{{ if eq "${var.wait_for_host_enabled}" "true" }}muc_wait_for_host,{{ end }}muc_hide_all"
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

# Name your etherpad instance!
ETHERPAD_TITLE=Video Chat

# The default text of a pad
ETHERPAD_DEFAULT_PAD_TEXT="Welcome to Web Chat!\n\n"

# Name of the skin for etherpad
ETHERPAD_SKIN_NAME=colibris

# Skin variants for etherpad
ETHERPAD_SKIN_VARIANTS="super-light-toolbar super-light-editor light-background full-width-editor"

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

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# Minimum port for media used by Jigasi
JIGASI_PORT_MIN=20000

# Maximum port for media used by Jigasi
JIGASI_PORT_MAX=20050

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

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

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
        ENABLE_VISITORS="${var.visitors_enabled}"
        JICOFO_ENABLE_REST="1"
        VISITORS_MAX_PARTICIPANTS=5
        VISITORS_MAX_VISITORS_PER_NODE=250
        PROSODY_VISITORS_MUC_PREFIX="conference"
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
{{ range service "${var.shard}.prosody-vnode" -}}
    {{ scratch.MapSetX "vnodes" .ServiceMeta.vindex . -}}
{{ end -}}

VISITORS_XMPP_SERVER={{ range $i, $e := scratch.MapValues "vnodes" }}{{ if gt $i 0 }},{{ end }}{{ $e.Address }}:{{ $e.ServiceMeta.prosody_client_port}}{{ end }}
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

# Name your etherpad instance!
ETHERPAD_TITLE=Video Chat

# The default text of a pad
ETHERPAD_DEFAULT_PAD_TEXT="Welcome to Web Chat!\n\n"

# Name of the skin for etherpad
ETHERPAD_SKIN_NAME=colibris

# Skin variants for etherpad
ETHERPAD_SKIN_VARIANTS="super-light-toolbar super-light-editor light-background full-width-editor"

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

# XMPP user for Jigasi MUC client connections
JIGASI_XMPP_USER=jigasi

# MUC name for the Jigasi pool
JIGASI_BREWERY_MUC=jigasibrewery

# Minimum port for media used by Jigasi
JIGASI_PORT_MIN=20000

# Maximum port for media used by Jigasi
JIGASI_PORT_MAX=20050

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

# Container restart policy
# Defaults to unless-stopped
RESTART_POLICY=unless-stopped

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

    task "web" {
      driver = "docker"
      config {
        image        = "nginx:latest"
        ports = ["http","nginx-status"]
        volumes = ["local/nginx.conf:/etc/nginx/nginx.conf","local/nginx-site.conf:/etc/nginx/conf.d/default.conf","local/nginx-status.conf:/etc/nginx/conf.d/status.conf","local/nginx-streams.conf:/etc/nginx/conf.stream/default.conf"]
      }
      env {
        NGINX_WORKER_PROCESSES = 4
        NGINX_WORKER_CONNECTIONS = 1024

      }
      template {
        destination = "local/nginx.conf"
        # overriding the delimiters to [[ ]] to avoid conflicts with tpl's native templating, which also uses {{ }}

  data = <<EOF
user www-data;
worker_processes 4;
pid /run/nginx.pid;
#include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections 1024;
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
	include /etc/nginx/conf.d/*.conf;
}

stream {
    include /etc/nginx/conf.stream/*.conf;
}

#daemon off;

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
# upstream main prosody
upstream prosodylimitedupstream {
    server {{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }};
}
# local rate-limited proxy for main prosody
server {
    listen    15280;
    proxy_upload_rate 10k;
    proxy_pass prosodylimitedupstream;
}

{{ range service "${var.shard}.prosody-vnode" -}}
    {{ scratch.MapSetX "vnodes" .ServiceMeta.vindex . -}}
{{ end -}}

{{ range $i, $e := scratch.MapValues "vnodes" -}}
# upstream visitor prosody {{ $i }}
upstream prosodylimitedupstream{{ $i }} {
    server {{ $e.Address }}:{{ $e.Port }};
}
# local rate-limited proxy for visitor prosody {{ $i }}
server {
{{ $port := add 25280 $i -}}
    listen    {{ $port }};
    proxy_upload_rate 10k;
    proxy_pass prosodylimitedupstream{{ $i }};
}
{{ end -}}

EOF
        destination = "local/nginx-streams.conf"
      }

      template {
        data = <<EOF

{{ range service "release-${var.release_number}.jitsi-meet-web" -}}
    {{ scratch.SetX "web" .  -}}
{{ end -}}

upstream prosody {
    zone upstreams 64K;
    server {{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }};
    keepalive 2;
}

# local upstream for main prosody used in final proxy_pass directive
upstream prosodylimited {
    zone upstreams 64K;
    server 127.0.0.1:15280;
    keepalive 2;
}

# local upstream for web content used in final proxy_pass directive
upstream web {
    zone upstreams 64K;
{{ with scratch.Get "web" -}}
    server {{ .Address }}:{{ .Port }};
{{ else -}}
    server 127.0.0.1:15280;
{{ end -}}
    keepalive 2;
}

# local upstream for jicofo connection
upstream jicofo {
    zone upstreams 64K;
    server {{ env "NOMAD_IP_jicofo_http" }}:{{ env "NOMAD_HOST_PORT_jicofo_http" }};
    keepalive 2;
}

{{ range loop ${var.visitors_count} -}}
# local upstream for visitor prosody {{ . }} used in final proxy_pass directive
upstream prosodylimited{{ . }} {
    zone upstreams 64K;
{{ $port := add 25280 . -}}
    server 127.0.0.1:{{ $port }};
    keepalive 2;
}
{{ end -}}


{{ range service "${var.shard}.prosody-vnode" -}}
    {{ scratch.MapSetX "vnodes" .ServiceMeta.vindex . -}}
{{ end -}}

{{ range $i, $e := scratch.MapValues "vnodes" -}}
# upstream visitor prosody {{ $i }}
upstream v{{ $i }} {
    server {{ $e.Address }}:{{ $e.Port }};
}
{{ end -}}

map $arg_vnode $prosody_node {
    default prosody;
{{ range loop ${var.visitors_count} -}}
    v{{ . }} v{{ . }};
{{ end -}}
}

# map to determine which prosody to proxy based on query param 'vnode'
map $arg_vnode $prosody_bosh_node {
    default prosodylimited;
{{ range loop ${var.visitors_count} -}}
    v{{ . }} prosodylimited{{ . }};
{{ end -}}
}

limit_req_zone $remote_addr zone=conference-request:10m rate=5r/s;

# Set $remote_addr by scanning X-Forwarded-For, while only trusting the defined list of trusted proxies.
set_real_ip_from 127.0.0.1;
set_real_ip_from 172.0.0.0/8;
set_real_ip_from 10.0.0.0/8;
real_ip_header X-Forwarded-For;
real_ip_recursive on;

server {

    listen 80;

    server_name ${var.signal_api_domain_name};

    set $prefix "";

    location = /kick-participant {
        proxy_pass http://prosodylimited/kick-participant?prefix=$prefix&$args;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host '${var.domain}';
    }

    location ~ ^/([^/?&:'"]+)/kick-participant {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /kick-participant;
    }

    location ~ ^/room-password(/?)(.*)$ {
        proxy_pass http://prosodylimited/room-password$2$is_args$args;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host ${var.domain};

        proxy_buffering off;
        tcp_nodelay on;
    }

    location = /end-meeting {
        proxy_pass http://prosodylimited/end-meeting$is_args$args;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host ${var.domain};

        proxy_buffering off;
        tcp_nodelay on;
    }

    location = /invite-jigasi{
            proxy_pass http://prosodylimited/invite-jigasi$is_args$args;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host ${var.domain};

            proxy_buffering off;
            tcp_nodelay on;
    }

    location ~ ^/([^/?&:'"]+)/room-password$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /room-password;
    }

    location ~ ^/([^/?&:'"]+)/end-meeting$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /end-meeting;
    }

    location ~ ^/([^/?&:'"]+)/invite-jigasi$ {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /invite-jigasi;
    }
}


# main server doing the routing
server {
    listen       80 default_server;
    server_name  ${var.domain};

    add_header 'X-Jitsi-Shard' '${var.shard}';
    add_header 'X-Jitsi-Region' '${var.octo_region}';
    add_header 'X-Jitsi-Release' '${var.release_number}';

    # BOSH
    location = /http-bind {
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Expose-Headers' "Content-Type, X-Jitsi-Region, X-Jitsi-Shard, X-Proxy-Region, X-Jitsi-Release";
        add_header 'X-Jitsi-Shard' '${var.shard}';
        add_header 'X-Jitsi-Region' '${var.octo_region}';
        add_header 'X-Jitsi-Release' '${var.release_number}';
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host ${var.domain};

        proxy_pass http://$prosody_bosh_node/http-bind?prefix=$prefix&$args;
    }

    # xmpp websockets
    location = /xmpp-websocket {
        tcp_nodelay on;

        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Expose-Headers' "Content-Type, X-Jitsi-Region, X-Jitsi-Shard, X-Proxy-Region, X-Jitsi-Release";
        add_header 'X-Jitsi-Shard' '${var.shard}';
        add_header 'X-Jitsi-Region' '${var.octo_region}';
        add_header 'X-Jitsi-Release' '${var.release_number}';
        proxy_http_version 1.1;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Host ${var.domain};
        proxy_set_header X-Forwarded-For $remote_addr;

        proxy_pass http://$prosody_node/xmpp-websocket?prefix=$prefix&$args;
    }

    location ~ ^/conference-request/v1(\/.*)?$ {
        proxy_pass http://jicofo/conference-request/v1$1;
        limit_req zone=conference-request burst=5;
        add_header "Cache-Control" "no-cache, no-store";
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Expose-Headers' "Content-Type, X-Jitsi-Region, X-Jitsi-Shard, X-Proxy-Region, X-Jitsi-Release";

    }
    location ~ ^/([^/?&:'"]+)/conference-request/v1(\/.*)?$ {
            rewrite ^/([^/?&:'"]+)/conference-request/v1(\/.*)?$ /conference-request/v1$2;
    }


    # BOSH for subdomains
    location ~ ^/([^/?&:'"]+)/http-bind {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /http-bind;
    }

    # websockets for subdomains
    location ~ ^/([^/?&:'"]+)/xmpp-websocket {
        set $subdomain "$1.";
        set $subdir "$1/";
        set $prefix "$1";

        rewrite ^/(.*)$ /xmpp-websocket;
    }

    # shard health check
    location = /about/health {
        proxy_pass      http://{{ env "NOMAD_IP_signal_sidecar_http" }}:{{ env "NOMAD_HOST_PORT_signal_sidecar_http" }}/signal/health;
        # do not cache anything from prebind
        add_header "Cache-Control" "no-cache, no-store";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        add_header 'X-Jitsi-Shard' '${var.shard}';
        add_header 'X-Jitsi-Region' '${var.octo_region}';
        add_header 'X-Jitsi-Release' '${var.release_number}';
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Expose-Headers' "Content-Type, X-Jitsi-Region, X-Jitsi-Shard, X-Proxy-Region, X-Jitsi-Release";
    }


    location / {
        proxy_set_header X-Jitsi-Shard ${var.shard};
        proxy_hide_header 'X-Jitsi-Shard';
        proxy_set_header Host $http_host;

        proxy_pass http://web;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }

}
EOF
        destination = "local/nginx-site.conf"
      }
    }
  }
}