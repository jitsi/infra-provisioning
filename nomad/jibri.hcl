variable "pool_type" {
  type = string
  default = "jibri"
}

variable jibri_recorder_password {
    type = string
    default = "replaceme_recorder"
}

variable jibri_recorder_username {
    type = string
    default = "jibri"
}

variable jibri_xmpp_password {
    type = string
    default = "replaceme_jibri"
}

variable jibri_xmpp_username {
    type = string
    default = "jibri"
}

variable "jibri_tag" {
  type = string
}

variable "jibri_version" {
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

variable "jibri_usage_timeout" {
  type = string
  default = "61"
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
    jibri_version = "${var.jibri_version}"
    release_number = "${var.release_number}"
  }

  group "jibri" {

    volume "jibri" {
      type      = "host"
      read_only = false
      source    = "jibri"
    }

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
        to = 2222
      }
    }

    shutdown_delay = "10s"
    service {
      name = "jibri"
      tags = ["group-${NOMAD_META_group}","jibri-${NOMAD_ALLOC_ID}","ip-${attr.unique.network.ip-address}"]

      meta {
        domain = "${var.domain}"
        environment = "${meta.environment}"
        jibri_version = "${var.jibri_version}"
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
        path     = "/jibri/api/v1.0/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "jibri" {
      vault {
        change_mode = "noop"

      }

      driver = "docker"

      config {
        force_pull = true
        image        = "ghcr.io/jitsi/jibri:${var.jibri_tag}"
        cap_add = ["SYS_ADMIN"]
        # 2gb shm
        shm_size = 2147483648
        ports = ["http"]
        volumes = [
          "local/xmpp-servers:/opt/jitsi/xmpp-servers",
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
          "local/jibri-status.sh:/opt/jitsi/scripts/jibri-status.sh",
          "local/config:/config",
          # Migrated to s6-overlay v3 / rootless.
          #
          # env oneshot: seeds JIBRI_VERSION / XMPP_SERVER into the s6 container
          # environment, ordered before the image's 01-config.
          "local/jibri-env-type:/etc/s6-overlay/s6-rc.d/00-jibri-env/type",
          "local/jibri-env-up:/etc/s6-overlay/s6-rc.d/00-jibri-env/up",
          "local/jibri-env-contents:/etc/s6-overlay/s6-rc.d/user/contents.d/00-jibri-env",
          "local/jibri-env-config-dep:/etc/s6-overlay/s6-rc.d/01-config/dependencies.d/00-jibri-env",
          "local/jibri-env-script:/etc/s6-overlay/scripts/jibri-env",
          # status reporter: replaces the old cron (cron + netcat are not in the
          # rootless image and can't be apt-installed at runtime). A v3 longrun
          # loops every 60s; jibri-status.sh now sends statsd over bash /dev/udp.
          "local/jibri-status-type:/etc/s6-overlay/s6-rc.d/60-jibri-status/type",
          "local/jibri-status-run:/etc/s6-overlay/s6-rc.d/60-jibri-status/run",
          "local/jibri-status-dep:/etc/s6-overlay/s6-rc.d/60-jibri-status/dependencies.d/40-jibri",
          "local/jibri-status-contents:/etc/s6-overlay/s6-rc.d/user/contents.d/60-jibri-status",
          "local/jibri-status-loop:/etc/s6-overlay/scripts/jibri-status-loop"
    	  ]
      }
      volume_mount {
        volume      = "jibri"
        destination = "/mnt/recordings"
        read_only   = false
      }

      env {
        XMPP_ENV_NAME = "${var.environment}"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JIBRI_RECORDER_USER = "${var.jibri_recorder_username}"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_USER = "${var.jibri_xmpp_username}"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
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
        DISPLAY=":0"
        JIBRI_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        JIBRI_FINALIZE_RECORDING_SCRIPT_PATH = "/usr/bin/jitsi_uploader.sh"
        JIBRI_RECORDING_DIR = "/mnt/recordings"
        // JIBRI_STATSD_HOST = "${attr.unique.network.ip-address}"
        // JIBRI_STATSD_PORT = "8125"
        ENABLE_STATS_D = "false"
        JIBRI_ENABLE_PROMETHEUS = "true"
        JIBRI_USAGE_TIMEOUT = "${var.jibri_usage_timeout} minutes"
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

      # --- 00-jibri-env: oneshot seeding JIBRI_VERSION / XMPP_SERVER into the s6
      # container environment, ordered before the image's 01-config. The script
      # both exports (so reload-config.sh can source it) and writes the s6
      # container_environment (so longrun services started later see the values). ---
      template {
        data = <<EOF
oneshot
EOF
        destination = "local/jibri-env-type"
        perms = "644"
      }
      template {
        data = <<EOF
/etc/s6-overlay/scripts/jibri-env
EOF
        destination = "local/jibri-env-up"
        perms = "644"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jibri-env-contents"
        perms = "644"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jibri-env-config-dep"
        perms = "644"
      }
      template {
        data = <<EOF
#!/command/with-contenv bash
JIBRI_VERSION="$(dpkg -s jibri | grep Version | awk '{print $2}' | sed 's/..$//')"
export JIBRI_VERSION
printf '%s' "$JIBRI_VERSION" > /run/s6/container_environment/JIBRI_VERSION

XMPP_SERVER="$(cat /opt/jitsi/xmpp-servers/servers)"
export XMPP_SERVER
printf '%s' "$XMPP_SERVER" > /run/s6/container_environment/XMPP_SERVER
EOF
        destination = "local/jibri-env-script"
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
#!/command/with-contenv bash

# Refresh XMPP_SERVER from the updated servers file, re-render config into
# /run/jibri/config, then ask jibri to reconnect to the new shard list.
. /etc/s6-overlay/scripts/jibri-env
/etc/s6-overlay/scripts/config
/opt/jitsi/jibri/reload.sh
EOF
        destination = "local/reload-config.sh"
        perms = "755"
      }

      # --- 60-jibri-status: v3 longrun that runs jibri-status.sh every 60s,
      # replacing the old per-minute cron (cron is not in the rootless image). ---
      template {
        data = <<EOF
longrun
EOF
        destination = "local/jibri-status-type"
        perms = "644"
      }
      template {
        data = <<EOF
#!/command/execlineb -P

/etc/s6-overlay/scripts/jibri-status-loop
EOF
        destination = "local/jibri-status-run"
        perms = "755"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jibri-status-dep"
        perms = "644"
      }
      template {
        data = <<EOF
# managed by nomad
EOF
        destination = "local/jibri-status-contents"
        perms = "644"
      }
      template {
        data = <<EOF
#!/command/with-contenv bash

while true; do
  sleep 60
  /opt/jitsi/scripts/jibri-status.sh
done
EOF
        destination = "local/jibri-status-loop"
        perms = "755"
      }

      template {
        data = <<EOF
#!/command/with-contenv bash

[ -z "$JIBRI_STATSD_HOST" ] && JIBRI_STATSD_HOST="localhost"
[ -z "$JIBRI_STATSD_PORT" ] && JIBRI_STATSD_PORT="8125"
[ -z "$JIBRI_HTTP_API_EXTERNAL_PORT" ] && JIBRI_HTTP_API_EXTERNAL_PORT="2222"
[ -z "$JIBRI_VERSION" ] && JIBRI_VERSION="$(dpkg -s jibri | grep Version | awk '{print $2}' | sed 's/..$//')"

JIBRI_STATSD_TAGS="role:java-jibri,jibri_version:$JIBRI_VERSION,jibri:$JIBRI_INSTANCE_ID"

CURL_BIN="/usr/bin/curl"

STATUS_URL="http://localhost:$JIBRI_HTTP_API_EXTERNAL_PORT/jibri/api/v1.0/health"

STATUS_TIMEOUT=30

function getJibriStatus() {
    $CURL_BIN --max-time $STATUS_TIMEOUT $STATUS_URL 2>/dev/null
}

#pessimism FTW
availableValue=0
healthyValue=0
recordingValue=0
STATUS=`getJibriStatus`
if [ $? == 0 ]; then
  #parse status into pieces
  recordingStatus=$(echo $STATUS | jq -r ".status.busyStatus")
  healthyStatus=$(echo $STATUS | jq -r ".status.health.healthStatus")

  #if we got a jibri response we're probably healthy?
  if [[ $healthyStatus == "HEALTHY" ]]; then
    healthyValue=1
  else
    healthyValue=0
  fi

  #mostly assume recording is available unless recording status is BUSY
  if [[ "$recordingStatus" == "BUSY" ]]; then
    availableValue=0
    recordingValue=1
  else
    availableValue=1
    recordingValue=0
  fi
fi

#if jibri is unhealthy, mark it as unavailable as well
if [[ $healthyValue -eq 0 ]]; then
    availableValue=0
fi

# send metrics to statsd over UDP via bash /dev/udp (netcat is not in the
# rootless image). Each redirection opens, writes one datagram, and closes.
sendStatsd() {
    echo "$1" > "/dev/udp/$JIBRI_STATSD_HOST/$JIBRI_STATSD_PORT" 2>/dev/null || true
}
sendStatsd "jibri.available:$availableValue|g|#$JIBRI_STATSD_TAGS"
sendStatsd "jibri.healthy:$healthyValue|g|#$JIBRI_STATSD_TAGS"
sendStatsd "jibri.recording:$recordingValue|g|#$JIBRI_STATSD_TAGS"

EOF
        destination = "local/jibri-status.sh"
        perms = "755"
      }

      resources {
        cpu    = 2500
        memory = 3072
      }
    }


  }
}
