variable "jitsi_repo" {
    type = string
    default = "jitsi"
}

variable "pool_type" {
  type = string
  default = "general"
}

variable jigasi_transcriber_user {
    type = string
    default = "transcribera"
}

variable jigasi_transcriber_password {
    type = string
    default = "replaceme_transcriber"
}

variable jigasi_xmpp_user {
    type = string
    default = "jigasia"
}

variable jigasi_xmpp_password {
    type = string
    default = "replaceme_jigasi"
}

variable "jigasi_tag" {
  type = string
}

variable "jigasi_version" {
  type = string
  default = "latest"
}

variable "dc" {
  type = string
}

variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "release_number" {
  type = string
  default = "0"
}

variable "gcloud_environment_type" {
  type = string
  default = "stage"
}

# This declares a job named "docs". There can be exactly one
# job declaration per job file.
job "[JOB_NAME]" {
  # Specify this job should run in the region named "global". Regions
  # are defined by the Nomad servers' configuration.
  region = "global"

  datacenters = ["${var.dc}"]

  # Run this job as a "service" type. Each job type has different
  # properties. See the documentation below for more examples.
  type = "batch"

  parameterized {
    payload = "required"
    meta_required = ["group", "name"]
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  meta {
    jigasi_version = "${var.jigasi_version}"
    release_number = "${var.release_number}"
  }

  group "transcriber" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    count = 1

    network {
      mode = "bridge"
      # This requests a dynamic port named "http". This will
      # be something like "46283", but we refer to it via the
      # label "http".
      port "http" {
        to = 8788
      }
    }

    service {
      name = "transcriber"
      tags = ["group-${NOMAD_META_group}","transcriber-${NOMAD_ALLOC_ID}","ip-${attr.unique.network.ip-address}"]

      meta {
        domain = "${var.domain}"
        environment = "${meta.environment}"
        jigasi_version = "${var.jigasi_version}"
        nomad_allocation = "${NOMAD_ALLOC_ID}"
        group = "${NOMAD_META_group}"
        release_number = "${var.release_number}"
      }

      port = "http"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "autoscaler"
              local_bind_port  = 2223
            }
          }
        }
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/about/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "transcriber" {
      vault {
        change_mode = "noop"

      }

      driver = "docker"

      config {
        force_pull = true
        image        = "${var.jitsi_repo}/jigasi:${var.jigasi_tag}"
        cap_add = ["SYS_ADMIN"]
        # 2gb shm
        shm_size = 2147483648
        ports = ["http"]
        volumes = [
          "local/xmpp-servers:/opt/jitsi/xmpp-servers",
          "local/01-xmpp-servers:/etc/cont-init.d/01-xmpp-servers",
#          "local/11-status-cron:/etc/cont-init.d/11-status-cron",
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
#          "local/jibri-status.sh:/opt/jitsi/scripts/jigasi-stats.sh",
#          "local/cron-service-run:/etc/services.d/60-cron/run",
          "local/config:/config"
    	  ]
      }

      env {
        XMPP_ENV_NAME = "${var.environment}"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JIGASI_TRANSCRIBER_USER = "${var.jigasi_transcriber_user}"
        JIGASI_TRANSCRIBER_PASSWORD = "${var.jigasi_transcriber_password}"
        JIGASI_XMPP_USER = "${var.jigasi_xmpp_user}"
        JIGASI_XMPP_PASSWORD = "${var.jigasi_xmpp_password}"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
        BOSH_URL_PATTERN="https://{host}{subdomain}/http-bind?room={roomName}"
        JIGASI_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        JIGASI_ENABLE_PROMETHEUS = "true"
        JIGASI_MODE = "transcriber"
        LOCAL_ADDRESS = "${attr.unique.network.ip-address}"
        AUTOSCALER_SIDECAR_PORT = "6000"
#        AUTOSCALER_URL = "https://${meta.cloud_name}-autoscaler.jitsi.net"
        AUTOSCALER_URL = "http://localhost:2223"
        AUTOSCALER_SIDECAR_KEY_FILE = "/secrets/asap.key"
        AUTOSCALER_SIDECAR_REGION = "${meta.cloud_region}"
        AUTOSCALER_SIDECAR_GROUP_NAME = "${NOMAD_META_group}"
        AUTOSCALER_SIDECAR_INSTANCE_ID = "${NOMAD_JOB_ID}"
#        CHROMIUM_FLAGS="--start-maximized,--kiosk,--enabled,--autoplay-policy=no-user-gesture-required,--use-fake-ui-for-media-stream,--enable-logging,--v=1"
      }

      template {
        data = <<EOF
{{ with secret "secret/default/transcriber/googlecloud-${var.gcloud_environment_type}" }}
GC_PROJECT_ID="{{ .Data.data.project_id }}"
GC_PRIVATE_KEY_ID="{{ .Data.data.private_key_id }}"
GC_PRIVATE_KEY={{ .Data.data.private_key | toJSON }}
GC_CLIENT_EMAIL="{{ .Data.data.client_email }}"
GC_CLIENT_ID="{{ .Data.data.client_id }}"
GC_CLIENT_CERT_URL="{{ .Data.data.client_x509_cert_url }}"
{{ end }}
EOF
        env = true
        destination = "secrets/google_cloud"
      }

      template {
        data = <<EOF
AUTOSCALER_SIDECAR_KEY_ID="{{ with secret "secret/${var.environment}/asap/server" }}{{ .Data.data.key_id }}{{ end }}"
EOF
        env = true
        destination = "secrets/asap_key_id"
      }

      template {
        data = <<EOF
{{- with secret "secret/${var.environment}/asap/server" }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/asap.key"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
export JIGASI_VERSION="$(dpkg -s jigasi | grep Version | awk '{print $2}' | sed 's/..$//')"
echo -n "$JIGASI_VERSION" > /var/run/s6/container_environment/JIGASI_VERSION

export XMPP_SERVER="$(cat /opt/jitsi/xmpp-servers/servers)"
echo -n "$XMPP_SERVER" > /var/run/s6/container_environment/XMPP_SERVER
EOF
        destination = "local/01-xmpp-servers"
        perms = "755"
      }

      template {
        data = <<EOF
{{ range $index, $item := service "signal" -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
{{ end -}}
{{ range $index, $item := service "all" -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.domain $item  -}}
{{ end -}}
{{ range $sindex, $item := scratch.MapValues "shards" -}}{{ if gt $sindex 0 -}},{{end}}{{ .Address }}:{{ with .ServiceMeta.prosody_client_port}}{{.}}{{ else }}5222{{ end }}{{ end -}}
EOF

        destination = "local/xmpp-servers/servers"
        # instead of restarting, jibri will graceful shutdown when shard list changes
        change_mode = "script"
        change_script {
          command = "/opt/jitsi/scripts/reload-config.sh"
          timeout = "6h"
          fail_on_error = true
        }
      }
      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

. /etc/cont-init.d/01-xmpp-servers
/etc/cont-init.d/10-config
/usr/share/jigasi/reconfigure_xmpp.sh
EOF
        destination = "local/reload-config.sh"
        perms = "755"
      }

      resources {
        cpu    = 1000
        memory = 3072
      }
    }


  }
}