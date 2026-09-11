variable "dc" {
  type = string
}

variable "mimir_hostname" {
  type = string
}

variable "oracle_s3_namespace" {
  type = string
}

variable "internal_dns_zone" {
  type = string
  default = "oracle.infra.jitsi.net"
}

# Mimir supports N -> N+1 rolling upgrades only; never skip a minor version.
# See doc/mimir-runbook.md before bumping.
variable "mimir_version" {
  type = string
  default = "3.1.5"
}

variable "environment_type" {
  type = string
  description = "prod or nonprod; sizes the task resources"
  default = "nonprod"
}

# Block retention in object storage. The compactor owns deletion; the bucket has
# no lifecycle policy on purpose.
variable "retention_period" {
  type = string
  default = "2160h"
}

# Per-tenant limits (single tenant "anonymous"). These are deliberately NOT the
# Mimir defaults (150k series / 10k samples/s), which are far below what a
# region's telegraf fleet produces, but they are also not unlimited: with RF=3
# every ingester holds every series, so the series cap is what protects the
# 3 GB / 8 GB task memory from a cardinality explosion. Re-derive from
# prometheus_tsdb_head_series of the region being migrated before prod rollout.
variable "max_global_series_per_user" {
  type = number
  default = 1000000
}

variable "ingestion_rate" {
  type = number
  description = "samples/s per tenant"
  default = 250000
}

variable "ingestion_burst_size" {
  type = number
  default = 1000000
}

locals {
  mimir = [0, 1, 2]
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  priority    = 75

  # One group (= one zone = one ingester replica) at a time. RF=3 keeps write
  # quorum (2/3) with one zone down. An ingester restart replays its WAL from
  # the host volume before /ready goes 200, so the deadlines are generous.
  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "10m"
    progress_deadline = "15m"
    auto_revert       = true
    stagger           = "60s"
  }

  dynamic "group" {
    for_each = local.mimir
    labels   = ["mimir-${group.key}"]
    content {
      count = 1
      restart {
        attempts = 3
        interval = "10m"
        delay    = "25s"
        mode     = "delay"
      }
      network {
        mode = "host"
        port "http" {
        }
        port "grpc" {
        }
        # loki-cluster owns static 7946 on the same consul nodes.
        port "gossip" {
          static = 7947
        }
      }
      constraint {
        attribute  = "${meta.pool_type}"
        value     = "consul"
      }
      # /mnt/bv/mimir-N, attached by tag to the consul node with group-index N
      # (terraform/volumes-mimir). Holds the ingester WAL + head block, ring
      # tokens, store-gateway index headers and compactor scratch.
      volume "mimir" {
        type      = "host"
        read_only = false
        source    = "mimir-${group.key}"
      }

      task "mimir" {
        driver = "docker"
        user = "root"

        # noop on purpose: a Vault credential rotation must not bounce all three
        # ingesters at once. Roll the new secret in with a normal (rolling)
        # deploy instead -- see doc/mimir-runbook.md.
        vault {
          change_mode = "noop"
        }

        config {
          network_mode = "host"
          image = "grafana/mimir:${var.mimir_version}"
          args = [
            "-config.file=/local/mimir.yaml",
          ]
          ports = ["http", "gossip", "grpc"]
        }
        volume_mount {
          volume      = "mimir"
          destination = "/mimir"
          read_only   = false
        }
        template {
          destination = "local/mimir.yaml"
          # noop: consul service churn (alertmanager moving hosts) must not
          # restart a stateful ingester. Config changes ship as a new job
          # version, which rolls one group at a time.
          change_mode = "noop"
          data = <<EOH
# Grafana Mimir ${var.mimir_version}, monolithic mode, 3 replicas per region.
# Validated against the 3.x configuration reference; do not copy 2.x examples.
target: all
multitenancy_enabled: false
no_auth_tenant: anonymous

usage_stats:
  enabled: false

activity_tracker:
  filepath: /mimir/metrics-activity.log

api:
  prometheus_http_prefix: /prometheus

server:
  http_listen_address: 0.0.0.0
  http_listen_port: {{ env "NOMAD_HOST_PORT_http" }}
  grpc_listen_address: 0.0.0.0
  grpc_listen_port: {{ env "NOMAD_HOST_PORT_grpc" }}
  log_level: warn

common:
  storage:
    backend: s3
    s3:
      endpoint: ${var.oracle_s3_namespace}.compat.objectstorage.{{ env "meta.cloud_region" }}.oraclecloud.com:443
      region: {{ env "meta.cloud_region" }}
      bucket_name: mimir-{{ env "meta.environment" }}
      # OCI's S3-compat endpoint needs path-style addressing (loki/tempo do the same).
      bucket_lookup_type: path
      insecure: false
{{ with secret "secret/default/mimir/s3" }}
      access_key_id: {{ .Data.data.access_key }}
      secret_access_key: {{ .Data.data.secret_key }}
{{ end }}

# One bucket, three prefixes.
blocks_storage:
  storage_prefix: blocks
  tsdb:
    dir: /mimir/tsdb
  bucket_store:
    sync_dir: /mimir/tsdb-sync

ruler_storage:
  storage_prefix: ruler

alertmanager_storage:
  storage_prefix: alertmanager

memberlist:
  # Stops a misrouted packet from another memberlist cluster (loki on 7946)
  # from ever being accepted.
  cluster_label: mimir-${var.dc}
  bind_port: {{ env "NOMAD_HOST_PORT_gossip" }}
  advertise_addr: {{ env "NOMAD_IP_gossip" }}
  advertise_port: {{ env "NOMAD_HOST_PORT_gossip" }}
  # Seeds are the consul-node DNS names; after a consul-node rotation the name
  # points at a new host, so periodically re-join to heal any split.
  rejoin_interval: 1m
  join_members:
    - ${var.dc}-consul-a.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}
    - ${var.dc}-consul-b.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}
    - ${var.dc}-consul-c.${var.internal_dns_zone}:{{ env "NOMAD_HOST_PORT_gossip" }}

# Every ring member registers as the STABLE identity mimir-N with tokens
# persisted on the host volume, so a consul-node rotation or alloc reschedule
# rejoins as the same member with the same tokens (no unhealthy squatter, no
# resharding). Tokens files live at the top of the volume: Mimir does not
# create parent directories for them.
ingester:
  ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}
    instance_port: {{ env "NOMAD_HOST_PORT_grpc" }}
    instance_availability_zone: zone-${group.key}
    replication_factor: 3
    zone_awareness_enabled: true
    tokens_file_path: /mimir/ingester-tokens
    unregister_on_shutdown: false
    final_sleep: 0s
    min_ready_duration: 15s

distributor:
  ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}
  # HA dedup for the two alloy scrapers (cluster / __replica__ labels). The
  # elected-replica state must be shared by all distributors, so it lives in
  # the consul KV of the local consul cluster, not in per-process memory.
  ha_tracker:
    enable_ha_tracker: true
    kvstore:
      store: consul
      prefix: mimir/ha-tracker/
      consul:
        host: {{ env "NOMAD_IP_grpc" }}:8500

store_gateway:
  sharding_ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}
    instance_availability_zone: zone-${group.key}
    replication_factor: 3
    zone_awareness_enabled: true
    tokens_file_path: /mimir/store-gateway-tokens
    unregister_on_shutdown: false
    wait_stability_min_duration: 1m

compactor:
  data_dir: /mimir/compactor
  sharding_ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}

ruler:
  rule_path: /mimir/ruler
  ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}

# 3.x queriers have their own lifecycler. Without an explicit address it
# auto-detects from interfaces eth0/en0 and refuses to start on hosts that name
# them differently (OCI: ens3/enp*), so every ring member gets its address from
# Nomad rather than from interface detection.
querier:
  ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}

# Ring-based scheduler discovery so every query-frontend sees all three
# schedulers (the default DNS mode would need a stable scheduler address).
query_scheduler:
  service_discovery_mode: ring
  ring:
    kvstore:
      store: memberlist
    instance_id: mimir-${group.key}
    instance_addr: {{ env "NOMAD_IP_grpc" }}

frontend:
  address: {{ env "NOMAD_IP_grpc" }}

limits:
  # HA tracker (see distributor.ha_tracker). Only alloy's *scraped* streams carry
  # cluster/__replica__; OTLP-relayed and alloy self metrics must not (they
  # would be dropped as "non-elected replica").
  accept_ha_samples: true
  ha_cluster_label: cluster
  ha_replica_label: __replica__
  max_global_series_per_user: ${var.max_global_series_per_user}
  ingestion_rate: ${var.ingestion_rate}
  ingestion_burst_size: ${var.ingestion_burst_size}
  # telegraf inputs carry many labels; the default of 30 would silently discard.
  max_label_names_per_series: 60
  # tolerate agent WAL replay after an alloy or distributor restart
  out_of_order_time_window: 5m
  compactor_blocks_retention_period: ${var.retention_period}
  # Ruler notifications. No rules are loaded until JIT-16017 syncs the alert
  # catalog; the target list is rendered once at alloc start (change_mode noop
  # above), so that ticket must decide between a re-render strategy and
  # Mimir's own alertmanager.
  ruler_alertmanager_client_config:
    alertmanager_url: {{ range $i, $s := service "alertmanager" }}{{ if ne $i 0 }},{{ end }}http://{{ $s.Address }}:{{ $s.Port }}{{ end }}
EOH
        }
        resources {
          cpu    = "%{ if var.environment_type == "prod" }2000%{ else }1000%{ endif }"
          memory = "%{ if var.environment_type == "prod" }8192%{ else }3072%{ endif }"
        }
        shutdown_delay = "10s"
        service {
          name = "mimir"
          port = "http"
          tags = ["int-urlprefix-${var.mimir_hostname}/", "ip-${attr.unique.network.ip-address}","mimir-${group.key}"]
          check {
            name     = "Mimir healthcheck"
            port     = "http"
            type     = "http"
            path     = "/ready"
            interval = "20s"
            timeout  = "5s"
            # /ready stays 503 while the ingester replays its WAL and joins the
            # ring; a 60s grace (loki's value) would restart a large ingester in
            # a loop and never let it come up.
            check_restart {
              limit           = 3
              grace           = "10m"
              ignore_warnings = false
            }
          }
          meta {
            mimir_index = "${group.key}"
          }
        }
      }
    }
  }
}
