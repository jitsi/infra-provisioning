variable "pool_type" {
  type = string
  default = "general"
}

variable jibri_recorder_password {
    type = string
    default = "replaceme_recorder"
}

variable jibri_xmpp_password {
    type = string
    default = "replaceme_jibri"
}

variable "jibri_tag" {
  type = string
}

variable "jibri_version" {
  type = string
  default = "latest"
}

variable "environment_type" {
  type = string
  default = "stage"
}

variable "asap_jwt_kid" {
    type = string
    default = "replaceme"
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
  }

  group "jibri" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    count = 1

    network {
      # This requests a dynamic port named "http". This will
      # be something like "46283", but we refer to it via the
      # label "http".
      port "http" {
        to = 2222
      }
    }

    task "jibri" {
      driver = "docker"

      config {
        image        = "jitsi/jibri:${var.jibri_tag}"
        cap_add = ["SYS_ADMIN"]
        # 2gb shm
        shm_size = 2147483648
        ports = ["http"]
        volumes = [
	        "/opt/jitsi/keys:/opt/jitsi/keys",
          "local/xmpp-servers:/opt/jitsi/xmpp-servers",
          "local/01-xmpp-servers:/etc/cont-init.d/01-xmpp-servers",
          "local/11-status-cron:/etc/cont-init.d/11-status-cron",
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
          "local/jibri-status.sh:/opt/jitsi/scripts/jibri-status.sh",
          "local/cron-service-run:/etc/services.d/60-cron/run"
    	  ]
      }

      env {
        XMPP_ENV_NAME = "${var.environment}"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JIBRI_RECORDER_USER = "recorder"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_USER = "jibri"
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
        DISPLAY=":0"
        JIBRI_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        JIBRI_FINALIZE_RECORDING_SCRIPT_PATH = "/usr/bin/jitsi_uploader.sh"
        JIBRI_RECORDING_DIR = "/local/recordings"
        JIBRI_STATSD_HOST = "${attr.unique.network.ip-address}"
        JIBRI_STATSD_PORT = "8125"
        ENABLE_STATS_D = "true"
        LOCAL_ADDRESS = "${attr.unique.network.ip-address}"
        AUTOSCALER_SIDECAR_PORT = "6000"
        AUTOSCALER_SIDECAR_KEY_ID = "${var.asap_jwt_kid}"
        AUTOSCALER_URL = "https://${meta.cloud_name}-autoscaler.jitsi.net"
        AUTOSCALER_SIDECAR_KEY_FILE = "/opt/jitsi/keys/${var.environment_type}.key"
        AUTOSCALER_SIDECAR_REGION = "${meta.cloud_region}"
        AUTOSCALER_SIDECAR_GROUP_NAME = "${NOMAD_META_group}"
        AUTOSCALER_SIDECAR_INSTANCE_ID = "${NOMAD_JOB_ID}"
#        CHROMIUM_FLAGS="--start-maximized,--kiosk,--enabled,--autoplay-policy=no-user-gesture-required,--use-fake-ui-for-media-stream,--enable-logging,--v=1"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
export JIBRI_VERSION="$(dpkg -s jibri | grep Version | awk '{print $2}' | sed 's/..$//')"
echo -n "$JIBRI_VERSION" > /var/run/s6/container_environment/JIBRI_VERSION

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
/opt/jitsi/jibri/reload.sh
EOF
        destination = "local/reload-config.sh"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

apt-get update && apt-get -y install cron netcat

echo '* * * * * /opt/jitsi/scripts/jibri-status.sh' | crontab 

EOF
        destination = "local/11-status-cron"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

exec cron -f

EOF
        destination = "local/cron-service-run"
        perms = "755"

      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

[ -z "$JIBRI_STATSD_HOST" ] && JIBRI_STATSD_HOST="localhost"
[ -z "$JIBRI_STATSD_PORT" ] && JIBRI_STATSD_PORT="8125"
[ -z "$JIBRI_HTTP_API_EXTERNAL_PORT" ] && JIBRI_HTTP_API_EXTERNAL_PORT="2222"
[ -z "$JIBRI_VERSION" ] && JIBRI_VERSION="$(dpkg -s jibri | grep Version | awk '{print $2}' | sed 's/..$//')"

JIBRI_STATSD_TAGS="role:java-jibri,jibri_version:$JIBRI_VERSION,jibri:$JIBRI_INSTANCE_ID"

CURL_BIN="/usr/bin/curl"
NC_BIN="/bin/nc"

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

# send metrics to statsd
echo "jibri.available:$availableValue|g|#$JIBRI_STATSD_TAGS" | $NC_BIN -C -w 1 -u $JIBRI_STATSD_HOST $JIBRI_STATSD_PORT
echo "jibri.healthy:$healthyValue|g|#$JIBRI_STATSD_TAGS" | $NC_BIN -C -w 1 -u $JIBRI_STATSD_HOST $JIBRI_STATSD_PORT
echo "jibri.recording:$recordingValue|g|#$JIBRI_STATSD_TAGS" | $NC_BIN -C -w 1 -u $JIBRI_STATSD_HOST $JIBRI_STATSD_PORT

EOF
        destination = "local/jibri-status.sh"
        perms = "755"
      }

      resources {
        cpu    = 8000
        memory = 2048
      }
    }


  }
}