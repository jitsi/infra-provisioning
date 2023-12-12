job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [ "[[ var "datacenter" . ]]" ]

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
    jvb_version = "[[ env "CONFIG_jvb_version" ]]"
  }

  group "jvb" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "[[ env "CONFIG_pool_type" ]]"
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
        image        = "jitsi/jvb:[[ env "CONFIG_jvb_tag" ]]"
        cap_add = ["SYS_ADMIN"]
        ports = ["http","media","colibri"]
        volumes = [
          "/opt/jitsi/keys:/opt/jitsi/keys",
          "local/xmpp-servers:/opt/jitsi/xmpp-servers",
          "local/01-xmpp-servers:/etc/cont-init.d/01-xmpp-servers",
          // "local/11-status-cron:/etc/cont-init.d/11-status-cron",
          "local/reload-config.sh:/opt/jitsi/scripts/reload-config.sh",
          "local/jvb-status.sh:/opt/jitsi/scripts/jvb-status.sh",
          // "local/cron-service-run:/etc/services.d/60-cron/run"
          "local/config:/config",
    	  ]
      }

      env {
        JVB_PORT="${NOMAD_HOST_PORT_media}"
        DOCKER_HOST_ADDRESS="${meta.public_ip}"
        XMPP_ENV_NAME = "[[ env "CONFIG_environment" ]]"
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        JVB_POOL_MODE="[[ env "CONFIG_jvb_pool_mode" ]]"
        SHARD="[[ env "CONFIG_shard" ]]"
        RELEASE_NUMBER="[[ env "CONFIG_release_number" ]]"
        # JVB auth password
        JVB_AUTH_USER="jvb"
        JVB_AUTH_PASSWORD = "[[ env "CONFIG_jvb_auth_password" ]]"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.[[ env "CONFIG_domain" ]]"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.[[ env "CONFIG_domain" ]]"
        ENABLE_JVB_XMPP_SERVER="1"

        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.[[ env "CONFIG_domain" ]]"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.[[ env "CONFIG_domain" ]]"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        DISPLAY=":0"
        JVB_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        LOCAL_ADDRESS = "${attr.unique.network.ip-address}"
        AUTOSCALER_SIDECAR_PORT = "6000"
        AUTOSCALER_SIDECAR_KEY_ID = "[[ env "CONFIG_asap_jwt_kid" ]]"
        // AUTOSCALER_URL = "https://${meta.cloud_name}-autoscaler.jitsi.net"
        AUTOSCALER_SIDECAR_KEY_FILE = "/opt/jitsi/keys/[[ env "CONFIG_environment_type" ]].key"
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

export JVB_XMPP_SERVER="$(cat /opt/jitsi/xmpp-servers/servers)"
echo -n "$JVB_XMPP_SERVER" > /var/run/s6/container_environment/JVB_XMPP_SERVER
EOF
        destination = "local/01-xmpp-servers"
        perms = "755"
      }

      template {
        data = <<EOF
[[ $pool_mode := or (env "CONFIG_jvb_pool_mode") "shard" -]]
[[ if eq $pool_mode "remote" "global" -]]
{{ range $dcidx, $dc := datacenters -}}
  [[ if eq $pool_mode "remote" -]]
  {{ if ne $dc "[[ var "datacenter" . ]]" -}}
  [[ end -]]
  {{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal@" $dc -}}
  {{range $index, $item := service $service -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
  {{ end -}}
  [[ if eq $pool_mode "remote" -]]
  {{ end -}}
  [[ end -]]
{{ end -}}
[[ else -]]
  [[ if eq $pool_mode "local" -]]
{{ $service := print "release-" (envOrDefault "RELEASE_NUMBER" "0") ".signal" -}}
  [[ else -]]
{{ $service := print "shard-" (env "SHARD") ".signal" -}}
  [[ end -]]
{{range $index, $item := service $service -}}
  {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
{{ end -}}
[[ end -]]
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