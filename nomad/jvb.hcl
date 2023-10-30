variable "pool_type" {
  type = string
  default = "JVB"
}

variable jvb_auth_password {
    type = string
    default = "replaceme_jvb"
}

variable "jvb_tag" {
  type = string
}

variable "jvb_version" {
  type = string
  default = "latest"
}

variable "jvb_pool_mode" {
  type = string
  default = "shard"
}

variable "shard" {
  type = string
  default = "default"
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

variable "release_number" {
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
    jvb_version = "${var.jvb_version}"
  }

  group "jvb" {

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
        to = 8080
      }
      port "media" {}
      port "colibri" {
        to = 9090
      }
    }

    task "jvb" {
      driver = "docker"

      config {
        image        = "aaronkvanmeerten/jvb:${var.jvb_tag}"
        cap_add = ["SYS_ADMIN"]
        # 2gb shm
        shm_size = 2147483648
        ports = ["http","media","colibri"]
        volumes = [
          "/opt/jitsi/keys:/opt/jitsi/keys",
          "local/xmpp-servers:/opt/jitsi/xmpp-servers",
          "local/01-xmpp-servers:/etc/cont-init.d/01-xmpp-servers",
          "local/11-status-cron:/etc/cont-init.d/11-status-cron",
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
          "local/jvb-status.sh:/opt/jitsi/scripts/jvb-status.sh",
          "local/cron-service-run:/etc/services.d/60-cron/run"
    	  ]
      }

      env {
        XMPP_ENV_NAME = "${var.environment}"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JVB_POOL_MODE="${var.jvb_pool_mode}"
        SHARD="${var.shard}"
        RELEASE_NUMBER="${var.release_number}"
        # JVB auth password
        JVB_AUTH_USER=jvb
        JVB_AUTH_PASSWORD = "${var.jvb_auth_password}"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.${var.domain}"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.${var.domain}"
        ENABLE_JVB_XMPP_SERVER="1"

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
        JVB_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
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
export JVB_VERSION="$(dpkg -s jitsi-videobridge2 | grep Version | awk '{print $2}' | sed 's/..$//')"
echo -n "$JVB_VERSION" > /var/run/s6/container_environment/JVB_VERSION

export XMPP_SERVER="$(cat /opt/jitsi/xmpp-servers/servers)"
echo -n "$XMPP_SERVER" > /var/run/s6/container_environment/XMPP_SERVER
EOF
        destination = "local/01-xmpp-servers"
        perms = "755"
      }

      template {
        data = <<EOF
{{ $pool_mode := envOrDefault "JVB_POOL_MODE" "shard" -}}
{{ if eq $pool_mode "remote" "global" -}}
  {{ range $dcidx, $dc := datacenters -}}
    {{ if or (and (eq $pool_mode "remote") (ne $dcidx 0)) (eq $pool_mode "global") -}}
      {{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal@" $dc -}}
      {{range $index, $item := service $service -}}
        {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
      {{ end -}}
    {{ end -}}
  {{ end -}}
{{ else -}}
  {{ if eq $pool_mode "local" -}}
    {{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal" -}}
    {{ scratch.Set "service" $service -}}
  {{ else -}}
    {{ $service := print "shard-" (env "SHARD") ".signal" -}}
    {{ scratch.Set "service" $service -}}
  {{ end -}}
  {{ $service := scratch.Get "service" -}}
  {{range $index, $item := service $service -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
  {{ end -}}
{{ end -}}
{{ range $sindex, $item := scratch.MapValues "shards" -}}{{ if gt $sindex 0 -}},{{end}}{{ .Address }}:{{ with .ServiceMeta.prosody_jvb_client_port}}{{.}}{{ else }}6222{{ end }}{{ end -}}
EOF

        destination = "local/xmpp-servers/servers"
        # instead of restarting, JVB will graceful shutdown when shard list changes
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
/opt/jitsi/jvb/reload.sh
EOF
        destination = "local/reload-config.sh"
        perms = "755"
      }

//       template {
//         data = <<EOF
// #!/usr/bin/with-contenv bash

// apt-get update && apt-get -y install cron netcat

// echo '* * * * * /opt/jitsi/scripts/jvb-status.sh' | crontab 

// EOF
//         destination = "local/11-status-cron"
//         perms = "755"
//       }

//       template {
//         data = <<EOF
// #!/usr/bin/with-contenv bash

// exec cron -f

// EOF
//         destination = "local/cron-service-run"
//         perms = "755"

//       }

//       template {
//         data = <<EOF
// #!/usr/bin/with-contenv bash

// # TODO: implement jvb stats here
// EOF
//         destination = "local/jvb-status.sh"
//         perms = "755"
//       }

      resources {
        cpu    = 4000
        memory = 2048
      }
    }

  }
}