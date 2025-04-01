variable "dc" {
  type = string
}

variable "environment" {
  type = string
}

variable "dns_zone" {
  type = string
  default = "jitsi.net"
}

variable "app_version" {
  type = string
  default = "latest"
}

variable "log_level" {
  type = string
  default = "INFO"
}

variable "queue_id" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  group "multitrack-recorder" {
    count = 2

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 8989
      }
    }

    task "multitrack-recorder" {
      vault {
        change_mode = "noop"
      }
      service {
        name = "multitrack-recorder"
        tags = [
          "ip-${attr.unique.network.ip-address}",
          "int-urlprefix-${var.dc}-jmr.${var.dns_zone}/record/",
          "int-urlprefix-jmr.${var.dns_zone}/record/",
        ]
        port = "http"
        check {
          // check_restart {
          //   limit = 3
          //   grace = "90s"
          //   ignore_warnings = false
          // }

          name     = "health"
          type     = "http"
          port     = "http"
          path     = "/metrics"
          interval = "10s"
          timeout  = "2s"
        }
        meta {
          metrics_port = "${NOMAD_HOST_PORT_http}"
        }
      }
    
      driver = "docker"

      config {
        image = "jitsi/jitsi-multitrack-recorder:${var.app_version}"
        ports = ["http"]
        volumes = [
          "local/jmr.conf:/defaults/jmr.conf",
          "local/boot-config:/etc/cont-init.d/08-boot-config",
          "secrets/oci:/root/.oci",
          "${NOMAD_ALLOC_DIR}/data:/data"
        ]
      }

      env {
        LOG_LEVEL = "${var.log_level}"
        JMR_FORMAT="mka"
        JMR_FINALIZE_WEBHOOK="https://${var.dc}-async-transcriber.${var.dns_zone}/finalize"
        JMR_FINALIZE_SCRIPT="/local/finalize.sh"
        JMR_BUCKET="multitrack-recorder-${var.environment}"
        JMR_REGION="${meta.cloud_region}"
        JMR_QUEUE_ID="${var.queue_id}"
      }

      template {
        data = <<EOF
jitsi-multitrack-recorder {
  recording {
    format = "mka"
    directory = "/data"
  }
  finalize-script = "/local/finalize.sh"
}
EOF
        destination = "local/jmr.conf"
        perms = "644"
      }

      template {
        data = <<EOF
[DEFAULT]
{{- $secret_path := printf "secret/%s/multitrack-recorder/oci_api_${var.environment}" (env "NOMAD_NAMESPACE") }}
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
        uid = 0
        gid = 0
      }

      template {
        data = <<EOF
{{- $secret_path := printf "secret/%s/multitrack-recorder/oci_api_${var.environment}" (env "NOMAD_NAMESPACE") }}
{{- with secret $secret_path }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/oci/oci_api_key.pem"
        perms = "600"
        uid = 0
        gid = 0
      }


      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
set -x
apt-dpkg-wrap apt-get update
apt-dpkg-wrap apt-get install -y python3-pip
pip install oci-cli --break-system-packages
EOF
        destination = "local/boot-config"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

set -e
set -x 

MEETING_ID=$1
DIR=$2
FORMAT=$3


echo "Running $0 for $MEETING_ID, $DIR, $FORMAT" 

if [[ "$FORMAT" == "MKA" ]] ;then
  FILENAME="recording-$(date +%Y%m%d-%H%M%S).mka"
  oci os object put --bucket-name $JMR_BUCKET --file "${DIR}/recording.mka" --name "recordings/${MEETING_ID}/${FILENAME}" --content-type "audio/x-matroska" --region $JMR_REGION
  if [ $? -eq 0 ]; then
    echo "Uploaded $FILENAME to $JMR_BUCKET"
    rm -rf $DIR
  else
    echo "Failed to upload ${DIR}/recording.mka to bucket $JMR_BUCKET file recordings/${MEETING_ID}/${FILENAME}"
  fi
  PAYLOAD="[{\"id\":\"${MEETING_ID}\",\"path\":\"recordings/${MEETING_ID}/${FILENAME}\"}]"
  oci queue messages put-messages --queue-id $JMR_QUEUE_ID --messages "$PAYLOAD" --region $JMR_REGION 
  RET=$?
  if [ $RET -eq 0 ]; then
    echo "Message queued for $MEETING_ID"
  else
    echo "Failed to queue message for $MEETING_ID"
    exit $RET
  fi
fi
EOF
        destination = "local/finalize.sh"
        perms = "755"
      }



      resources {
        cpu    = 1000
        memory = 4000
      }

    }
  }
}
