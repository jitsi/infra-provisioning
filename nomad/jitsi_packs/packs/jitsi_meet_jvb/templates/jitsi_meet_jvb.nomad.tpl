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
      tags = ["pool-[[ env "CONFIG_shard" ]]","release-[[ env "CONFIG_release_number" ]]","jvb-${NOMAD_ALLOC_ID}"]

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

echo $JVB_NAT_PORT > 
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
      driver = "docker"

      config {
        image        = "jitsi/jvb:[[ env "CONFIG_jvb_tag" ]]"
        cap_add = ["SYS_ADMIN"]
        ports = ["http","media","colibri"]
        volumes = [
          "/opt/jitsi/keys:/opt/jitsi/keys",
          "local/reload-shards.sh:/opt/jitsi/scripts/reload-shards.sh",
          "local/01-jvb-env:/etc/cont-init.d/01-jvb-env",
          "local/config:/config",
          "local/jvb.conf:/defaults/jvb.conf",
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
        data = <<EOF
[[ template "shard-lookup" . ]]
{
  "shards": {
{{ range $sindex, $item := scratch.MapValues "shards" -}}
  {{ scratch.SetX "domain" .ServiceMeta.domain -}}
  {{ if ne $sindex 0}},{{ end }}
    "{{.ServiceMeta.shard}}": {
      "shard":"{{.ServiceMeta.shard}}",
      "domain":"{{ .ServiceMeta.domain }}",
      "address":"{{.Address}}",
      "xmpp_host_private_ip_address":"{{.Address}}",
      "host_port":"{{ with .ServiceMeta.prosody_jvb_client_port}}{{.}}{{ else }}6222{{ end }}"
    }
{{ end -}}
  },
  "drain_mode":"false",
  "port": 6222,
  "domain":"auth.jvb.{{ scratch.Get "domain" }}",
  "muc_jids":"jvbbrewery@muc.jvb.{{ scratch.Get "domain" }}",
  "username":"[[ or (env "CONFIG_jvb_auth_username") "jvb" ]]",
  "password":"[[ env "CONFIG_jvb_auth_password" ]]",
  "muc_nickname":"jvb-{{ env "NOMAD_ALLOC_ID" }}",
  "iq_handler_mode":"[[ or (env "CONFIG_jvb_iq_handler_mode") "sync" ]]"
}
EOF
        destination = "local/config/shards.json"
        # instead of restarting, JVB will graceful shutdown when shard list changes
        change_mode = "script"
        change_script {
          command = "/opt/jitsi/scripts/reload-shards.sh"
          timeout = "6h"
          fail_on_error = true
        }
      }

      template {
        destination = "local/config/xmpp.conf"
        # instead of restarting, JVB will graceful shutdown when shard list changes
        change_mode = "noop"
        data = <<EOF
[[ template "shard-lookup" . ]]
videobridge.apis.xmpp-client.configs {
{{ range $sindex, $item := scratch.MapValues "shards" -}}
    # SHARD {{ .ServiceMeta.shard }}
    {{ .ServiceMeta.shard }} {
        HOSTNAME={{ .Address }}
        PORT={{ with .ServiceMeta.prosody_jvb_client_port}}{{.}}{{ else }}6222{{ end }}
        DOMAIN=auth.jvb.{{ .ServiceMeta.domain }}
        MUC_JIDS="jvbbrewery@muc.jvb.{{ .ServiceMeta.domain }}"
        USERNAME=[[ or (env "CONFIG_jvb_auth_username") "jvb" ]]
        PASSWORD=[[ env "CONFIG_jvb_auth_password" ]]
        MUC_NICKNAME=jvb-{{ env "NOMAD_ALLOC_ID" }}
        IQ_HANDLER_MODE=[[ or (env "CONFIG_jvb_iq_handler_mode") "sync" ]]
        # TODO: don't disable :(
        DISABLE_CERTIFICATE_VERIFICATION=true
    }
{{ end -}}
}
EOF
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

#!/bin/bash

SHARD_FILE=/config/shards.json
UPLOAD_FILE=/config/upload.json
DRAIN_URL="http://localhost:8080/colibri/drain"
LIST_URL="http://localhost:8080/colibri/muc-client/list"
ADD_URL="http://localhost:8080/colibri/muc-client/add"
REMOVE_URL="http://localhost:8080/colibri/muc-client/remove"

DRAIN_MODE=$(cat $SHARD_FILE | jq -r ".drain_mode")
DOMAIN=$(cat $SHARD_FILE | jq -r ".domain")
USERNAME=$(cat $SHARD_FILE | jq -r ".username")
PASSWORD=$(cat $SHARD_FILE | jq -r ".password")
MUC_JIDS=$(cat $SHARD_FILE | jq -r ".muc_jids")
MUC_NICKNAME=$(cat $SHARD_FILE | jq -r ".muc_nickname")
IQ_HANDLER_MODE=$(cat $SHARD_FILE | jq -r ".iq_handler_mode")
DISABLE_CERT_VERIFY="true"
XMPP_PORT=$(cat $SHARD_FILE | jq -r ".port")

SHARDS=$(cat $SHARD_FILE | jq -r ".shards|keys|.[]")
for SHARD in $SHARDS; do
    echo "Adding shard $SHARD"
    SHARD_IP=$(cat $SHARD_FILE | jq -r ".shards.\"$SHARD\".xmpp_host_private_ip_address")
    SHARD_PORT=$(cat $SHARD_FILE | jq -r ".shards.\"$SHARD\".host_port")
    if [[ "[[" ]] "$SHARD_PORT" == "null" ]]; then
        SHARD_PORT=$XMPP_PORT
    fi
    T="
{
    \"id\":\"$SHARD\",
    \"domain\":\"$DOMAIN\",
    \"hostname\":\"$SHARD_IP\",
    \"port\":\"$SHARD_PORT\",
    \"username\":\"$USERNAME\",
    \"password\":\"$PASSWORD\",
    \"muc_jids\":\"$MUC_JIDS\",
    \"muc_nickname\":\"$MUC_NICKNAME\",
    \"iq_handler_mode\":\"$IQ_HANDLER_MODE\",
    \"disable_certificate_verification\":\"$DISABLE_CERT_VERIFY\"
}"

    #configure JVB to know about shard via POST
    echo $T > $UPLOAD_FILE
    curl --data-binary "@$UPLOAD_FILE" -H "Content-Type: application/json" $ADD_URL
    rm $UPLOAD_FILE
done

LIVE_DRAIN_MODE="$(curl $DRAIN_URL | jq '.drain')"
if [[ "[[" ]] "$DRAIN_MODE" == "true" ]]; then
    if [[ "[[" ]] "$LIVE_DRAIN_MODE" == "false" ]]; then
        echo "Drain mode is requested, draining JVB"
        curl -d "" "$DRAIN_URL/enable"
    fi
fi
if [[ "[[" ]] "$DRAIN_MODE" == "false" ]]; then
    if [[ "[[" ]] "$LIVE_DRAIN_MODE" == "true" ]]; then
        echo "Drain mode is disabled, setting JVB to ready"
        curl -d "" "$DRAIN_URL/disable"
    fi
fi

LIVE_SHARD_ARR="$(curl $LIST_URL)"
FILE_SHARD_ARR="$(cat $SHARD_FILE | jq ".shards|keys")"
REMOVE_SHARDS=$(jq -r -n --argjson FILE_SHARD_ARR "$FILE_SHARD_ARR" --argjson LIVE_SHARD_ARR "$LIVE_SHARD_ARR" '{"live": $LIVE_SHARD_ARR,"file":$FILE_SHARD_ARR} | .live-.file | .[]')

for SHARD in $REMOVE_SHARDS; do
    echo "Removing shard $SHARD"
    curl -H "Content-Type: application/json" -X POST -d "{\"id\":\"$SHARD\"}" $REMOVE_URL 
done

EOF
        destination = "local/reload-shards.sh"
        perms = "755"
      }

      resources {
        cpu    = 4000
        memory = 2048
      }
    }

  }
}