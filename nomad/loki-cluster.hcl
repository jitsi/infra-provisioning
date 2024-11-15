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

variable "internal_dns_zone" {
  type = string
  default = "oracle.infra.jitsi.net"
}

variable "retention_period" {
  type = string
  default = "744h"
}

locals {
  loki = [0, 1, 2]
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  priority    = 75

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
        mode = "host"
        port "http" {
        }
        port "gossip" {
          static = 7946
        }
        port "grpc" {
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
          network_mode = "host"
          image = "grafana/loki:3.2.1"
          args = [
            "-config.file",
            "local/local-config.yaml",
          ]
          ports = ["http","gossip","grpc"]
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
    http_listen_port: {{ env "NOMAD_HOST_PORT_http" }}
    http_listen_address: 0.0.0.0
    grpc_listen_port: {{ env "NOMAD_HOST_PORT_grpc" }}
    grpc_listen_address: 0.0.0.0

  common:
    ring:
      instance_addr: {{ env "NOMAD_IP_grpc" }}
      kvstore:
        store: memberlist
    replication_factor: 1
    path_prefix: /loki # Update this accordingly, data will be stored here.

  memberlist:
    advertise_addr: {{ env "NOMAD_IP_grpc" }}
    tls_insecure_skip_verify: true
    join_members:
    # You can use a headless k8s service for all distributor, ingester and querier components.
    # :7946 is the default memberlist port.
    - ${var.dc}-consul-a.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}
    - ${var.dc}-consul-b.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}
    - ${var.dc}-consul-c.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}

  ingester:
    lifecycler:
      address: {{ env "NOMAD_IP_grpc" }}
      final_sleep: 0s
    # Any chunk not receiving new logs in this time will be flushed
    chunk_idle_period: 1h
    # All chunks will be flushed when they hit this age, default is 1h
    max_chunk_age: 1h
    # Loki will attempt to build chunks up to 1.5MB, flushing if chunk_idle_period or max_chunk_age is reached first
    chunk_target_size: 1048576
    # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
    chunk_retain_period: 30s
    #max_transfer_retries: 0     # Chunk transfers disabled
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
      - from: "2024-11-16" # <---- A date in the future
        index:
          period: 24h
          prefix: index_
        object_store: s3
        schema: v13
        store: tsdb

  storage_config:
    tsdb_shipper:
      active_index_directory: /loki/data/tsdb-index
      cache_location: /loki/data/tsdb-cache
    aws:
      s3: s3://${var.oracle_s3_credentials}@${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com/loki-{{ env "meta.environment" }}
      region: {{ env "meta.cloud_region" }}
      endpoint: https://${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com:443
      s3forcepathstyle: true
      insecure: false
  compactor:
    working_directory: /tmp/loki/boltdb-shipper-compactor
    compaction_interval: 10m
    retention_enabled: true
    retention_delete_delay: 2h
    retention_delete_worker_count: 150
    delete_request_store: aws
  query_range:
    # make queries more cache-able by aligning them with their step intervals
    align_queries_with_step: true
    max_retries: 5
    cache_results: true

    # results_cache:
    #   cache:
    #     # We're going to use the in-process "FIFO" cache
    #     #enable_fifocache: true
#        fifocache:
#          size: 1024
#          validity: 24h

  limits_config:
    allow_structured_metadata: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    retention_period: ${var.retention_period}
    retention_stream:
    # Retain jigasi-transcriber logs for 14 days
    - selector: '{task="jigasi-transcriber"}'
      priority: 1
      period: 336h
    # Retain prosody audit logs for 90 days
    - selector: '{group="signal", task="prosody", level="audit"}'
      priority: 1
      period: 2160h
    split_queries_by_interval: 15m
  chunk_store_config:
#    max_look_back_period: 0s
  table_manager:
    retention_deletes_enabled: false
    retention_period: 0s
  frontend:
    log_queries_longer_than: 5s
    compress_responses: true
    address: 
  EOH
          destination = "local/local-config.yaml"
        }
        resources {
          cpu    = 1024
          memory = 4096
        }
        service {
          name = "loki"
          port = "http"
          tags = ["int-urlprefix-${var.loki_hostname}/", "ip-${attr.unique.network.ip-address}","loki-${group.key}"]
          check {
            name     = "Loki healthcheck"
            port     = "http"
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
          meta {
            loki_index = "${group.key}"
          }
        }
      }
    }
  }
}