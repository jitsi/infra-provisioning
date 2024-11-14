[[ $pool_mode := or (env "CONFIG_jvb_pool_mode") "shard" -]]

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

    service {
      name = "jvb"
      tags = ["pool-[[ env "CONFIG_shard" ]]","release-[[ env "CONFIG_release_number" ]]","jvb-${NOMAD_ALLOC_ID}", "ip-${attr.unique.network.ip-address}"]

      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
        http_port = "${NOMAD_HOST_PORT_http}"
        colibri_port = "${NOMAD_HOST_PORT_colibri}"
        media_port = "${NOMAD_HOST_PORT_media}"
        jvb_version = "[[ env "CONFIG_jvb_version" ]]"
        nomad_allocation = "${NOMAD_ALLOC_ID}"
        public_ip = "${meta.public_ip}"
        group = "${NOMAD_META_group}"
        jvb_pool_mode = "[[ or (env "CONFIG_jvb_pool_mode") "shard" ]]"
      }

      port = "http"

      check {
        name     = "health"
        type     = "http"
        path     = "/about/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }


    task "pick-a-port" {
      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      template {
        data = <<EOF
#!/bin/bash
MIN_NAT_PORT=10001
MAX_NAT_PORT=12000

FOUND_PORT=true
while $FOUND_PORT; do
  JVB_NAT_PORT=$(shuf -i $MIN_NAT_PORT-$MAX_NAT_PORT -n 1)
  iptables --list -t nat | grep udp | grep -q $JVB_NAT_PORT || FOUND_PORT=false
done

iptables -t nat -A PREROUTING -p UDP --dport $JVB_NAT_PORT -j DNAT --to-destination {{ env "NOMAD_ADDR_media" }}
iptables -A FORWARD -p UDP -d {{ env "NOMAD_IP_media" }} --dport $JVB_NAT_PORT -j ACCEPT

iptables --list > $NOMAD_ALLOC_DIR/data/iptables.txt
iptables --list -t nat > $NOMAD_ALLOC_DIR/data/iptables-nat.txt

echo $JVB_NAT_PORT > $NOMAD_ALLOC_DIR/data/JVB_NAT_PORT
consul kv put jvb_nat_ports/[[ env "CONFIG_environment" ]]/[[ env "CONFIG_shard" ]]/$NOMAD_ALLOC_ID $JVB_NAT_PORT
EOF
        destination = "alloc/data/pick-a-port.sh"
        perms = "755"
      }

      driver = "raw_exec"
      config {
        command = "alloc/data/pick-a-port.sh"
      }
    }

    task "clean-a-port" {
      lifecycle {
        hook = "poststop"
        sidecar = false
      }

      template {
        data = <<EOF
#!/bin/bash
JVB_NAT_PORT="$(cat $NOMAD_ALLOC_DIR/data/JVB_NAT_PORT)"
iptables --list -t nat | grep udp | grep $JVB_NAT_PORT

iptables -t nat -D PREROUTING -p UDP --dport $JVB_NAT_PORT -j DNAT --to-destination {{ env "NOMAD_ADDR_media" }}
iptables -D FORWARD -p UDP -d {{ env "NOMAD_IP_media" }} --dport $JVB_NAT_PORT -j ACCEPT

iptables --list > $NOMAD_ALLOC_DIR/data/iptables.txt
iptables --list -t nat > $NOMAD_ALLOC_DIR/data/iptables-nat.txt

consul kv delete jvb_nat_ports/[[ env "CONFIG_environment" ]]/[[ env "CONFIG_shard" ]]/$NOMAD_ALLOC_ID
EOF
        destination = "alloc/data/clean-a-port.sh"
        perms = "755"
      }

      driver = "raw_exec"
      config {
        command = "alloc/data/clean-a-port.sh"
      }
    }

    task "jvb" {
      vault {
        change_mode = "noop"

      }
      driver = "docker"

      config {
        image        = "jitsi/jvb:[[ env "CONFIG_jvb_tag" ]]"
        cap_add = ["SYS_ADMIN"]
        ports = ["http","media","colibri"]
        volumes = [
          "local/reload-shards.sh:/opt/jitsi/scripts/reload-shards.sh",
          "local/01-jvb-env:/etc/cont-init.d/01-jvb-env",
          "local/config:/config",
          "local/jvb.conf:/defaults/jvb.conf",
          "local/logging.properties:/defaults/logging.properties",
          "local/jvb-service-run:/etc/services.d/jvb/run",
          "local/11-jvb-rtcstats-push:/etc/cont-init.d/11-jvb-rtcstats-push",
          "local/jvb-rtcstats-push-service-run:/etc/services.d/60-jvb-rtcstats-push/run"

    	  ]
      }

      env {
        JVB_PORT="${NOMAD_HOST_PORT_media}"
        JVB_ADVERTISE_IPS="${meta.public_ip}"
        XMPP_ENV_NAME = "[[ env "CONFIG_environment" ]]"
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        JVB_POOL_MODE="[[ env "CONFIG_jvb_pool_mode" ]]"
        SHARD="[[ env "CONFIG_shard" ]]"
        RELEASE_NUMBER="[[ env "CONFIG_release_number" ]]"
        # JVB auth password
        JVB_AUTH_USER="jvb"
        JVB_AUTH_PASSWORD = "[[ env "CONFIG_jvb_auth_password" ]]"
        JVB_LOG_FILE="/local/jvb.log"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.[[ env "CONFIG_domain" ]]"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.[[ env "CONFIG_domain" ]]"
        ENABLE_JVB_XMPP_SERVER="1"
        ENABLE_COLIBRI_WEBSOCKET="1"
        JVB_WS_SERVER_ID="jvb-${NOMAD_ALLOC_ID}"
        JVB_MUC_NICKNAME="jvb-${NOMAD_ALLOC_ID}"
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
        XMPP_HIDDEN_DOMAIN = "recorder.[[ env "CONFIG_domain" ]]"
        DISPLAY=":0"
        JVB_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
        LOCAL_ADDRESS = "${attr.unique.network.ip-address}"
        AUTOSCALER_SIDECAR_PORT = "6000"
        AUTOSCALER_URL = "https://${meta.cloud_name}-autoscaler.jitsi.net"
        AUTOSCALER_SIDECAR_KEY_FILE = "/secrets/asap.key"
        AUTOSCALER_SIDECAR_REGION = "${meta.cloud_region}"
        AUTOSCALER_SIDECAR_GROUP_NAME = "${NOMAD_META_group}"
        AUTOSCALER_SIDECAR_INSTANCE_ID = "${NOMAD_JOB_ID}"
        JVB_ADDRESS = "http://127.0.0.1:8080"
        RTCSTATS_SERVER="[[ env "CONFIG_jvb_rtcstats_push_rtcstats_server" ]]"
#        CHROMIUM_FLAGS="--start-maximized,--kiosk,--enabled,--autoplay-policy=no-user-gesture-required,--use-fake-ui-for-media-stream,--enable-logging,--v=1"
      }

      artifact {
        source      = "https://github.com/jitsi/jvb-rtcstats-push/releases/download/0.0.1/jvb-rtcstats-push.zip"
        mode = "file"
        destination = "local/jvb-rtcstats-push.zip"
        options {
          archive = false
        }
      }

      template {
        data = <<EOF
AUTOSCALER_SIDECAR_KEY_ID="{{ with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.key_id }}{{ end }}"
EOF
        env = true
        destination = "secrets/asap_key_id"
      }

      template {
        data = <<EOF
{{- with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/asap.key"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

export JAVA_SYS_PROPS="-Dnet.java.sip.communicator.SC_HOME_DIR_LOCATION=/ -Dnet.java.sip.communicator.SC_HOME_DIR_NAME=config -Djava.util.logging.config.file=/config/logging.properties -Dconfig.file=/config/jvb.conf"

DAEMON=/usr/share/jitsi-videobridge/jvb.sh

JVB_CMD="exec $DAEMON"
[ -n "$JVB_LOG_FILE" ] && JVB_CMD="$JVB_CMD 2>&1 | tee $JVB_LOG_FILE"

exec s6-setuidgid jvb /bin/bash -c "$JVB_CMD"
EOF
        destination = "local/jvb-service-run"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

apt-get update && apt-get -y install unzip cron

mkdir -p /jvb-rtcstats-push
cd /jvb-rtcstats-push
unzip /local/jvb-rtcstats-push.zip

echo '0 * * * * /local/jvb-log-truncate.sh' | crontab 

EOF
        destination = "local/11-jvb-rtcstats-push"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

echo > $JVB_LOG_FILE
EOF
        destination = "local/jvb-log-truncate.sh"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

exec node /jvb-rtcstats-push/app.js

EOF
        destination = "local/jvb-rtcstats-push-service-run"
        perms = "755"

      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
export JVB_VERSION="$(dpkg -s jitsi-videobridge2 | grep Version | awk '{print $2}' | sed 's/..$//')"
echo -n "$JVB_VERSION" > /var/run/s6/container_environment/JVB_VERSION

export JVB_NAT_PORT="$(cat /alloc/data/JVB_NAT_PORT)"
echo -n "$JVB_NAT_PORT" > /var/run/s6/container_environment/JVB_NAT_PORT
EOF
        destination = "local/01-jvb-env"
        perms = "755"
      }


      template {
        destination = "local/jvb.conf"
        change_mode = "noop"
        left_delimiter = "[{"
        right_delimiter = "}]"
        data = <<EOF
[[ template "jvb-config" . ]]
EOF
      }

      template {
        destination = "local/logging.properties"
        left_delimiter = "[{"
        right_delimiter = "}]"
        data = <<EOF
[[ template "logging-properties" . ]]
EOF
      }

      template {
        data = <<EOF
[[ template "shards-json" . ]]
EOF
        destination = "local/config/shards.json"
        # instead of restarting, JVB will reconfigure when shard list changes
        change_mode = "script"
        change_script {
          command = "/opt/jitsi/scripts/reload-shards.sh"
          timeout = "6h"
          #fail_on_error = true
        }
      }

      template {
        destination = "local/config/xmpp.conf"
        # instead of restarting, JVB will reconfigure when shard list changes
        change_mode = "noop"
        data = <<EOF
[[ template "xmpp-config" . ]]
EOF
      }

      template {
        data = <<EOF
[[ template "reload-shards" . ]]
EOF
        destination = "local/reload-shards.sh"
        perms = "755"
        change_mode = "noop"
      }

      resources {
        cpu    = 4000
        memory = 4096
      }
    }

  }
}