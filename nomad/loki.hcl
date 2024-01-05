variable "dc" {
  type = string
}

variable "loki_hostname" {
  type = string
}

variable "oracle_s3_namespace" {
  type = string
}

variable "oracle_s3_credentials" {
  type = string
}

locals {
  loki = [0, 1, 2]
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
  }

  dynamic "group" {
    for_each = local.loki
    labels   = ["loki-${group.key}"]
    content {
      count = 1
      restart {
        attempts = 3
        interval = "5m"
        delay    = "25s"
        mode     = "delay"
      }
      network {
        port "loki" {
          to = 3100
        }
        port "gossip" {
          static = 7946
        }
      }
      constraint {
        attribute  = "${meta.pool_type}"
        value     = "consul"
      }
      volume "loki" {
        type      = "host"
        read_only = false
        source    = "loki-${group.key}"
      }

      task "loki" {
        driver = "docker"
        user = "root"
        config {
          image = "grafana/loki:2.9.1"
          args = [
            "-config.file",
            "local/loki/local-config.yaml",
          ]
          ports = ["loki","gossip"]
        }
        volume_mount {
          volume      = "loki"
          destination = "/loki"
          read_only   = false
        }
        template {
          data = <<EOH
  auth_enabled: false
  server:
    http_listen_port: 3100

  common:
    ring:
      instance_addr: 127.0.0.1
      kvstore:
        store: memberlist
    replication_factor: 1
    path_prefix: /loki # Update this accordingly, data will be stored here.

  memberlist:
    join_members:
    # You can use a headless k8s service for all distributor, ingester and querier components.
    - loki.service.consul:7946 # :7946 is the default memberlist port.

  ingester:
    lifecycler:
      address: 127.0.0.1
      ring:
        kvstore:
          store: inmemory
        replication_factor: 1
      final_sleep: 0s
    # Any chunk not receiving new logs in this time will be flushed
    chunk_idle_period: 1h
    # All chunks will be flushed when they hit this age, default is 1h
    max_chunk_age: 1h
    # Loki will attempt to build chunks up to 1.5MB, flushing if chunk_idle_period or max_chunk_age is reached first
    chunk_target_size: 1048576
    # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
    chunk_retain_period: 30s
    max_transfer_retries: 0     # Chunk transfers disabled
  schema_config:
    configs:
      # New TSDB schema below
      - from: "2024-01-01" # <---- A date in the future
        index:
          period: 24h
          prefix: index_
        object_store: s3
        schema: v12
        store: tsdb

  storage_config:
    tsdb_shipper:
      active_index_directory: /loki/data/tsdb-index
      cache_location: /loki/data/tsdb-cache
      shared_store: s3
    aws:
      s3: s3://${var.oracle_s3_credentials}@${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com/loki-{{ env "meta.environment" }}
      region: {{ env "meta.cloud_region" }}
      endpoint: https://${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com:443
      s3forcepathstyle: true
      insecure: false
  compactor:
    working_directory: /tmp/loki/boltdb-shipper-compactor
    shared_store: s3
  limits_config:
    reject_old_samples: true
    reject_old_samples_max_age: 168h
  chunk_store_config:
    max_look_back_period: 0s
  table_manager:
    retention_deletes_enabled: false
    retention_period: 0s
  EOH
          destination = "local/loki/local-config.yaml"
        }
        resources {
          cpu    = 1024
          memory = 512
        }
        service {
          name = "loki"
          port = "loki"
          tags = ["int-urlprefix-${var.loki_hostname}/", "ip-${attr.unique.network.ip-address}","loki-${group.key}"]
          check {
            name     = "Loki healthcheck"
            port     = "loki"
            type     = "http"
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
      }
    }
  }
}