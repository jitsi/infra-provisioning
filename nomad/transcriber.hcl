variable "jitsi_repo" {
    type = string
    default = "ghcr.io/jitsi"
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
variable "oci_compartment" {
  type = string
  default = ""
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

variable "remote_config_url" {
  type = string
  default = "https://api-vo-pilot.jitsi.net/passcode/v1/settings"
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
      operator     = "set_contains_any"
      value    = "consul,general,transcriber"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "consul"
      weight    = -100
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
      weight    = 100
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

    shutdown_delay = "10s"
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
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
          "local/config:/config",
          # Migrated to s6-overlay v3 / rootless.
          #
          # env oneshot: seeds JIGASI_VERSION / XMPP_SERVER into the s6 container
          # environment, ordered before the image's 10-config.
          "local/jigasi-env-type:/etc/s6-overlay/s6-rc.d/00-jigasi-env/type",
          "local/jigasi-env-up:/etc/s6-overlay/s6-rc.d/00-jigasi-env/up",
          "local/jigasi-env-contents:/etc/s6-overlay/s6-rc.d/user/contents.d/00-jigasi-env",
          "local/jigasi-env-config-dep:/etc/s6-overlay/s6-rc.d/10-config/dependencies.d/00-jigasi-env",
          "local/jigasi-env-script:/etc/s6-overlay/scripts/jigasi-env",
          # jigasi's OCI transcription service reads ~/.oci/config; the rootless
          # image runs as the s6 user (uid 1000, HOME=/home/s6), not the old
          # jigasi user (uid 998, HOME=/usr/share/jigasi).
          "secrets/oci:/home/s6/.oci"
    	  ]

        # In transcriber mode the image's 10-config fails fast unless
        # /tmp/transcripts exists and is writable by uid 1000. It is a VOLUME in
        # the image, so docker would otherwise create it root-owned and 0755.
        mount {
          type   = "tmpfs"
          target = "/tmp/transcripts"
          tmpfs_options {
            size = 67108864
          }
        }
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
        XMPP_HIDDEN_DOMAIN = "recorder.${var.domain}"
        BOSH_URL_PATTERN="https://{host}{subdomain}/http-bind?room={roomName}"
        JIGASI_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        JIGASI_ENABLE_PROMETHEUS = "true"
        JIGASI_MODE = "transcriber"
        JIGASI_TRANSCRIBER_CUSTOM_SERVICE = "org.jitsi.jigasi.transcription.OracleTranscriptionService"
#        JIGASI_TRANSCRIBER_REMOTE_CONFIG_URL = "${var.remote_config_url}"
#        JIGASI_TRANSCRIBER_REMOTE_CONFIG_URL_AUD = "jitsi"
#        JIGASI_TRANSCRIBER_REMOTE_CONFIG_URL_KEY_PATH = "/secrets/asap.key"
        JIGASI_TRANSCRIBER_OCI_REGION = "${meta.cloud_region}"
        JIGASI_TRANSCRIBER_OCI_COMPARTMENT = "${var.oci_compartment}"
        JIGASI_TRANSCRIBER_WHISPER_URL = "wss://stage-8x8-api.jitsi.net/whisper/streaming-whisper/ws/"
        JIGASI_TRANSCRIBER_ENABLE_SAVING = "false"
        LOCAL_ADDRESS = "${attr.unique.network.ip-address}"
        AUTOSCALER_SIDECAR_PORT = "6000"
        SHUTDOWN_REST_ENABLED = "true"
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
{{ with secret "secret/${var.environment}/asap/server" }}
AUTOSCALER_SIDECAR_KEY_ID="{{ .Data.data.key_id }}"
JIGASI_TRANSCRIBER_WHISPER_PRIVATE_KEY_NAME="{{ .Data.data.key_id }}"
JIGASI_TRANSCRIBER_WHISPER_PRIVATE_KEY="{{ .Data.data.private_key | regexReplaceAll "(-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----)" "" | replaceAll "\n" "" }}"
JIGASI_TRANSCRIBER_REMOTE_CONFIG_URL_KEY_ID="{{ .Data.data.key_id }}"
{{ end }}
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
[DEFAULT]
{{- $secret_path := printf "secret/%s/transcriber/oci_api" (env "NOMAD_NAMESPACE") }}
{{- with secret $secret_path }}
user={{ .Data.data.user }}
fingerprint={{ .Data.data.fingerprint }}
key_file=/secrets/oci/oci_api_key.pem
tenancy={{ .Data.data.tenancy }}
region={{ env "meta.cloud_region" }}
{{ end -}}
EOF
        destination = "secrets/oci/config"
        perms = "600"
        uid = 1000
        gid = 1000
      }

      template {
        data = <<EOF
{{- $secret_path := printf "secret/%s/transcriber/oci_api" (env "NOMAD_NAMESPACE") }}
{{- with secret $secret_path }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/oci/oci_api_key.pem"
        perms = "600"
        uid = 1000
        gid = 1000
      }

      # --- 00-jigasi-env: oneshot seeding JIGASI_VERSION / XMPP_SERVER into the s6
      # container environment, ordered before the image's 10-config. The script
      # both exports (so reload-config.sh can source it) and writes the s6
      # container_environment (so services started later see the values). ---
      template {
        data = <<EOF
oneshot
EOF
        destination = "local/jigasi-env-type"
        perms = "644"
      }
      template {
        data = <<EOF
/etc/s6-overlay/scripts/jigasi-env
EOF
        destination = "local/jigasi-env-up"
        perms = "644"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jigasi-env-contents"
        perms = "644"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jigasi-env-config-dep"
        perms = "644"
      }
      template {
        data = <<EOF
#!/command/with-contenv bash
JIGASI_VERSION="$(dpkg -s jigasi | grep Version | awk '{print $2}' | sed 's/..$//')"
export JIGASI_VERSION
printf '%s' "$JIGASI_VERSION" > /run/s6/container_environment/JIGASI_VERSION

XMPP_SERVER="$(cat /opt/jitsi/xmpp-servers/servers)"
export XMPP_SERVER
printf '%s' "$XMPP_SERVER" > /run/s6/container_environment/XMPP_SERVER
EOF
        destination = "local/jigasi-env-script"
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
{{ range $sindex, $item := scratch.MapValues "shards" -}}{{ if gt $sindex 0 -}},{{end}}{{ .Address }}:{{ with .ServiceMeta.prosody_client_port}}{{.}}{{ else }}5222{{ end }}:{{ .ServiceMeta.shard }}{{ end -}}
EOF

        destination = "local/xmpp-servers/servers"
        # instead of restarting, transcriber will rebuild configuration disk then update running jigasi
        # re-adding every xmpp server in the configuration, and removing those no longer present on disk but still in the running configuration
        change_mode = "script"
        change_script {
          command = "/opt/jitsi/scripts/reload-config.sh"
          timeout = "6h"
          fail_on_error = true
        }
      }
      template {
        data = <<EOF
#!/bin/bash

# Nomad runs this through `docker exec`, whose PATH does not contain /command,
# so a #!/command/with-contenv shebang cannot be used here: execlineb cannot
# find its own builtins and the script dies with exit 127. Put /command on PATH
# (the image scripts called below do use with-contenv) and import the s6
# container environment by hand, which is what with-contenv would have done.
export PATH="/command:$PATH"
for _f in /run/s6/container_environment/*; do
    [ -f "$_f" ] || continue
    export "$(basename "$_f")=$(cat "$_f")"
done

# Refresh XMPP_SERVER from the updated servers file, re-render config into
# /run/jigasi/config, then re-add/remove call-control MUCs in running jigasi.
. /etc/s6-overlay/scripts/jigasi-env
/etc/s6-overlay/scripts/config
CONFIG_PATH=/run/jigasi/config/sip-communicator.properties /usr/share/jigasi/reconfigure_xmpp.sh
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