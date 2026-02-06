variable "dc" {
  type = string
}

variable "tempo_hostname" {
  type = string
}

variable "oracle_s3_namespace" {
  type = string
}

variable "tempo_version" {
  type = string
  default = "2.6.1"
}

variable "retention_period" {
  type = string
  default = "168h"
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
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

  group "tempo" {
    count = 1

    # Target general or consul pool
    constraint {
      attribute = "${meta.pool_type}"
      operator  = "set_contains_any"
      value     = "consul,general"
    }

    # Prefer general pool over consul pool
    affinity {
      attribute = "${meta.pool_type}"
      value     = "consul"
      weight    = -100
    }

    affinity {
      attribute = "${meta.pool_type}"
      value     = "general"
      weight    = 100
    }

    restart {
      attempts = 3
      delay    = "25s"
      interval = "5m"
      mode     = "delay"
    }

    network {
      mode = "bridge"
      port "otlp-grpc" {
        to = 4317
      }
      port "otlp-http" {
        to = 4318
      }
      port "http" {
        to = 3200
      }
    }

    # Service registration with internal Fabio routing
    service {
      name = "tempo"
      port = "http"
      tags = [
        "int-urlprefix-${var.tempo_hostname}/",
        "ip-${attr.unique.network.ip-address}"
      ]
      check {
        name     = "Tempo healthcheck"
        type     = "http"
        port     = "http"
        path     = "/ready"
        interval = "20s"
        timeout  = "5s"
        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "tempo" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "grafana/tempo:${var.tempo_version}"
        args  = [
          "-config.file=/etc/tempo/tempo.yaml"
        ]
        ports = ["otlp-grpc", "otlp-http", "http"]
        volumes = [
          "local/tempo.yaml:/etc/tempo/tempo.yaml"
        ]
      }

      template {
        destination   = "local/tempo.yaml"
        change_mode   = "restart"
        data = <<EOF
server:
  http_listen_port: 3200
  grpc_listen_port: 9095

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: ${var.retention_period}

storage:
  trace:
    backend: s3
    s3:
      bucket: tempo-{{ env "meta.environment" }}
      endpoint: ${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com:443
{{ with secret "secret/default/tempo/s3" }}
      access_key: {{ .Data.data.access_key }}
      secret_key: {{ .Data.data.secret_key }}
{{ end }}
      insecure: false
      forcepathstyle: true
    wal:
      path: /tmp/tempo/wal
    local:
      path: /tmp/tempo/blocks

metrics_generator:
  registry:
    external_labels:
      source: tempo
      cluster: {{ env "meta.environment" }}-{{ env "meta.cloud_region" }}
  storage:
    path: /tmp/tempo/generator/wal

overrides:
  defaults:
    metrics_generator:
      processors: []
EOF
      }

      resources {
        cpu    = 512
        memory = 1024
      }
    }
  }
}
