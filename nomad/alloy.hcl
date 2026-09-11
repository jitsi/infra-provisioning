variable "dc" {
  type = string
}

variable "alloy_hostname" {
  type = string
}

variable "top_level_domain" {
  type = string
  default = "jitsi.net"
}

variable "environment_type" {
  type = string
}

variable "alloy_loki_hostname" {
  type = string
}

# ---- metrics pipeline switches (doc/mimir-cluster-plan.md, Phase 2) ----

# Write metrics to the regional mimir-cluster (nomad/mimir-cluster.hcl). Off until
# the cluster exists in the region.
variable "enable_mimir_write" {
  type = bool
  default = false
}

# Keep relaying OTLP metrics to the legacy regional prometheus during the soak.
# Turned off at cutover (Phase 5), after which prometheus.hcl only scrapes for
# its own alert evaluation.
variable "enable_legacy_prometheus_write" {
  type = bool
  default = true
}

# Alloy takes over the consul-SD scrape jobs prometheus.hcl runs today. Both
# alloy replicas scrape everything; mimir's HA tracker keeps one copy.
variable "enable_scrape" {
  type = bool
  default = false
}

# How the *scraped* streams reach the external 8x8-hosted Mimir:
#   primary - only the alloc with NOMAD_ALLOC_INDEX 0 forwards, no HA labels
#             (safe when the external tenant has no HA dedup; ~30s gap on reschedule)
#   ha      - both replicas forward with cluster/__replica__ labels
#             (ONLY once the external tenant is confirmed to dedup on those labels,
#             otherwise every scraped series is doubled there)
#   none    - scraped streams stay local
variable "external_scrape_forward" {
  type = string
  default = "primary"
  validation {
    condition     = contains(["primary", "ha", "none"], var.external_scrape_forward)
    error_message = "The external_scrape_forward variable must be one of primary, ha or none."
  }
}

# Extra metric relabel rules applied to every scraped stream, in Alloy `rule {}`
# syntax (config/vars.yml alloy_custom_relabel_rules; the alloy translation of
# prometheus_custom_relabels).
variable "custom_relabel_rules" {
  type = string
  default = ""
}

# Extra external labels for the mimir writers, as Alloy map entries
# (config/vars.yml alloy_custom_external_labels).
variable "custom_external_labels" {
  type = string
  default = ""
}

locals {
  mimir_push_url = "https://[[ env \"meta.environment\" ]]-[[ env \"meta.cloud_region\" ]]-mimir.${var.top_level_domain}/api/v1/push"

  # receivers for OTLP-relayed metrics and alloy's own metrics (NO HA labels)
  direct_targets = compact([
    var.enable_legacy_prometheus_write ? "prometheus.remote_write.default.receiver" : "",
    var.enable_mimir_write ? "prometheus.remote_write.mimir.receiver" : "",
    "prometheus.remote_write.external.receiver",
  ])

  # receivers for the shared consul-SD scrape targets (HA-deduplicated)
  scrape_targets = compact([
    var.enable_mimir_write ? "prometheus.remote_write.mimir_ha.receiver" : "",
    var.external_scrape_forward != "none" ? "prometheus.relabel.external_ha_gate.receiver" : "",
  ])

  # job -> [consul service, scrape interval, service label ("" = leave as-is)]
  scrape_jobs = {
    alertmanager                   = ["alertmanager", "15s", "alertmanager"]
    cloudprober                    = ["cloudprober", "10s", "cloudprober"]
    telegraf                       = ["telegraf", "30s", ""]
    opus-transcriber-proxy-monitor = ["opus-transcriber-proxy-monitor", "30s", "jitsi"]
    gitea-mirror                   = ["gitea-mirror-metrics", "60s", "infra"]
    mimir                          = ["mimir", "15s", "infra"]
  }
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  # Spread across nodes for HA
  spread {
    attribute = "${node.unique.id}"
  }

  # Rolling update with canary
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

  group "alloy" {
    count = 2

    # Target general pool
    constraint {
      attribute = "${meta.pool_type}"
      operator  = "set_contains_any"
      value     = "consul,general"
    }

    # Distinct hosts for HA
    constraint {
      operator = "distinct_hosts"
      value    = "true"
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
      port "loki-push" {
        to = 3100
      }
      port "http" {
        to = 12345
      }
    }

    shutdown_delay = "10s"
    # Service registration with internal Fabio routing
    service {
      name = "alloy-otel"
      port = "otlp-http"
      tags = [
        "int-urlprefix-${var.alloy_hostname}/",
        "ip-${attr.unique.network.ip-address}"
      ]
      check {
        name     = "alloy health"
        type     = "http"
        port     = "http"
        path     = "/-/healthy"
        interval = "15s"
        timeout  = "5s"
      }
      meta {
        metrics_port = "${NOMAD_HOST_PORT_http}"
      }
    }

    # Service registration for Loki push API (accepts logs from Vector)
    service {
      name = "alloy-loki-push"
      port = "loki-push"
      tags = [
        "int-urlprefix-${var.alloy_loki_hostname}/",
        "ip-${attr.unique.network.ip-address}"
      ]
      check {
        name     = "alloy health"
        type     = "http"
        port     = "http"
        path     = "/-/healthy"
        interval = "15s"
        timeout  = "5s"
      }
    }

    task "alloy" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "grafana/alloy:latest"
        args  = [
          "run",
          "/etc/alloy/config.alloy",
          "--server.http.listen-addr=0.0.0.0:12345"
        ]
        ports = ["otlp-grpc", "otlp-http", "loki-push", "http"]
        volumes = [
          "local:/etc/alloy"
        ]
      }

      # Alloy configuration template
      template {
        destination   = "local/config.alloy"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        # Use [[ ]] delimiters to avoid conflicts with Alloy's native {{ }} templating
        left_delimiter  = "[["
        right_delimiter = "]]"
        data = <<EOF
// Loki Push API receiver - accepts logs from Vector in native Loki format
loki.source.api "vector" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 3100
  }
  forward_to = [loki.write.internal.receiver, loki.write.external.receiver]
}

// Internal Loki writer (for logs received via Loki push API from Vector)
loki.write "internal" {
  endpoint {
    url = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}/loki/api/v1/push"
  }
}

// OTEL Receiver - accepts logs, metrics, and traces via gRPC and HTTP
otelcol.receiver.otlp "default" {
  grpc {
    endpoint = "0.0.0.0:4317"
  }
  http {
    endpoint = "0.0.0.0:4318"
  }
  output {
    logs    = [otelcol.processor.batch.default.input]
    metrics = [otelcol.processor.batch.default.input]
    traces  = [otelcol.processor.batch.default.input]
  }
}

// Batch processor for better performance
otelcol.processor.batch "default" {
  output {
    logs    = [otelcol.processor.transform.loki_namespace.input]
    metrics = [otelcol.exporter.prometheus.default.input]
    traces  = [otelcol.exporter.otlphttp.tempo.input, otelcol.exporter.otlphttp.external_tempo.input]
  }
}

prometheus.exporter.self "self" {}

// Alloy's own metrics are per-instance and must NOT go through the HA-deduped
// writers (the non-elected replica's metrics would be dropped).
prometheus.relabel "add_labels" {
  forward_to = [${join(", ", local.direct_targets)}]
  rule {
    target_label = "alloy_type"
    replacement  = "internal"
  }
}

// Configure a prometheus.scrape component to collect Alloy metrics.
prometheus.scrape "demo" {
  targets    = prometheus.exporter.self.self.targets
  forward_to = [prometheus.relabel.add_labels.receiver]
}

// Add default namespace label to logs for Loki if not already set
otelcol.processor.transform "loki_namespace" {
  log_statements {
    context = "resource"
    statements = [
      `set(resource.attributes["namespace"], "default") where resource.attributes["namespace"] == nil`,
    ]
  }
  output {
    logs = [otelcol.exporter.otlphttp.loki.input, otelcol.exporter.loki.external_loki.input]
  }
}

// Export logs to Loki via internal LB (DNS routes through OCI internal LB -> Fabio)
// Loki's OTLP endpoint is at /otlp
otelcol.exporter.otlphttp "loki" {
  client {
    endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}/otlp"
  }
}

// Export traces to Tempo via internal LB. Uses the -tempo-otlp hostname (Tempo's
// OTLP ingest port 4318), NOT -tempo (the query API on 3200, which 404s on push).
otelcol.exporter.otlphttp "tempo" {
  client {
    endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-tempo-otlp.${var.top_level_domain}"
  }
}

// OTLP-relayed metrics. Each client sends to ONE alloy (via the LB), so these
// streams are not duplicated and must not carry HA labels.
otelcol.exporter.prometheus "default" {
  forward_to = [${join(", ", local.direct_targets)}]
}

%{ if var.enable_legacy_prometheus_write }
// Legacy regional prometheus (remote-write receiver). Removed at Phase 5 cutover.
prometheus.remote_write "default" {
  endpoint {
    url = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-prometheus.${var.top_level_domain}/api/v1/write"
  }
}
%{ endif }

%{ if var.enable_mimir_write }
// ---- Regional mimir-cluster ----
// Two writers to the same endpoint on purpose. Mimir's HA tracker decides per
// *request* from the first series' labels, so streams that carry
// cluster/__replica__ (shared scrape targets, scraped by both replicas) must never
// share a WAL/request with streams that don't (OTLP relays, alloy self metrics):
// a mixed batch would either be dropped wholesale or stored with a stray
// __replica__ label.

// direct: OTLP relays + alloy self metrics
prometheus.remote_write "mimir" {
  endpoint {
    url = "${local.mimir_push_url}"
  }
  external_labels = {
    "datacenter"  = "${var.dc}",
    "environment" = "[[ env "meta.environment" ]]",
    "region"      = "[[ env "meta.cloud_region" ]]",
    ${var.custom_external_labels}
  }
}

// HA-deduplicated: shared consul-SD scrape targets
prometheus.remote_write "mimir_ha" {
  endpoint {
    url = "${local.mimir_push_url}"
  }
  external_labels = {
    "datacenter"  = "${var.dc}",
    "environment" = "[[ env "meta.environment" ]]",
    "region"      = "[[ env "meta.cloud_region" ]]",
    "cluster"     = "[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]",
    "__replica__" = "alloy-[[ env "NOMAD_ALLOC_INDEX" ]]",
    ${var.custom_external_labels}
  }
}
%{ endif }

%{ if var.enable_scrape }
// ---- consul-SD scrape jobs (replacing prometheus.hcl's scrape_configs) ----
// Both alloy replicas scrape every target; dedup happens in mimir (HA tracker)
// and, in "ha" mode, in the external Mimir.
%{ for name, spec in local.scrape_jobs }
discovery.consul "${replace(name, "-", "_")}" {
  server           = "[[ env "NOMAD_IP_http" ]]:8500"
  services         = ["${spec[0]}"]
  refresh_interval = "30s"
}

prometheus.scrape "${replace(name, "-", "_")}" {
  targets         = discovery.consul.${replace(name, "-", "_")}.targets
  job_name        = "${name}"
  scrape_interval = "${spec[1]}"
  metrics_path    = "/metrics"
  forward_to      = [prometheus.relabel.${replace(name, "-", "_")}.receiver]
}

prometheus.relabel "${replace(name, "-", "_")}" {
  forward_to = [prometheus.relabel.scrape_common.receiver]
%{ if spec[2] != "" }
  rule {
    target_label = "service"
    replacement  = "${spec[2]}"
  }
%{ else }
  // no service label override for this job (matches prometheus.hcl)
  rule {
    action = "labeldrop"
    regex  = "__tmp_.*"
  }
%{ endif }
}
%{ endfor }

// Common metric relabels for every scraped stream, then fan out to the
// HA-deduplicated writers.
prometheus.relabel "scrape_common" {
  forward_to = [${join(", ", local.scrape_targets)}]
  // keeps the block valid when no custom rules are configured
  rule {
    action = "labeldrop"
    regex  = "__tmp_.*"
  }
${var.custom_relabel_rules}
}
%{ endif }

%{ if var.external_scrape_forward != "none" }
// Gate in front of the external HA writer. In "primary" mode only the alloc with
// index 0 forwards scraped streams externally; the other replica drops them here.
prometheus.relabel "external_ha_gate" {
  forward_to = [prometheus.remote_write.external_ha.receiver]
%{ if var.external_scrape_forward == "primary" }
  [[ if ne (env "NOMAD_ALLOC_INDEX") "0" ]]
  // not the primary replica: the external tenant has no HA dedup, drop everything
  rule {
    action        = "drop"
    source_labels = ["__name__"]
    regex         = ".*"
  }
  [[ else ]]
  // primary replica: pass through
  rule {
    action = "labeldrop"
    regex  = "__tmp_.*"
  }
  [[ end ]]
%{ else }
  rule {
    action = "labeldrop"
    regex  = "__tmp_.*"
  }
%{ endif }
}
%{ endif }

// --- External endpoints (Grafana Cloud) sourced from Vault ---
[[ with secret "secret/default/alloy/external-auth" ]]
// Auth for external Tempo
otelcol.auth.basic "external_tempo" {
  username = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-traces-username" ]]"
  password = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-traces-password" ]]"
}

// Export logs to external Loki (native Loki push API, not OTLP)
otelcol.exporter.loki "external_loki" {
  forward_to = [loki.write.external.receiver]
}

loki.write "external" {
  endpoint {
    url = "[[ index .Data.data "${var.environment_type}-01-oci-logs-url" ]]"
    basic_auth {
      username = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-logs-username" ]]"
      password = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-logs-password" ]]"
    }
  }
  external_labels = {
    "environment" = "[[ env "meta.environment" ]]",
    "region"      = "[[ env "meta.cloud_region" ]]",
  }
}

// Export traces to external Tempo
otelcol.exporter.otlphttp "external_tempo" {
  client {
    endpoint = "[[ index .Data.data "${var.environment_type}-01-oci-traces-url" | regexReplaceAll "/v1/traces$" "" ]]"
    auth     = otelcol.auth.basic.external_tempo.handler
    // The OCI o11y Tempo gateway is multi-tenant and rejects pushes without a
    // tenant header ("no org id" 503). Same convention as prometheus.hcl:
    // X-Scope-OrgID == the OCI username.
    headers = {
      "X-Scope-OrgID" = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-traces-username" ]]",
    }
  }
}

// Export metrics to external Mimir via remote write (OTLP relays + alloy self)
prometheus.remote_write "external" {
  endpoint {
    url = "[[ index .Data.data "${var.environment_type}-01-oci-metrics-url" ]]"
    basic_auth {
      username = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-metrics-username" ]]"
      password = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-metrics-password" ]]"
    }
  }
}

%{ if var.external_scrape_forward != "none" }
// Scraped streams to the external Mimir. Same tenant as "external" above; carries
// the labels the legacy prometheus.hcl remote_write attached, so the external
// alerting keeps working when prometheus.hcl stops writing.
prometheus.remote_write "external_ha" {
  endpoint {
    url = "[[ index .Data.data "${var.environment_type}-01-oci-metrics-url" ]]"
    basic_auth {
      username = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-metrics-username" ]]"
      password = "[[ index .Data.data "meetings-oci-hosts-${var.environment_type}-01-oci-metrics-password" ]]"
    }
  }
  external_labels = {
    "datacenter"  = "${var.dc}",
    "environment" = "[[ env "meta.environment" ]]",
    "region"      = "[[ env "meta.cloud_region" ]]",
%{ if var.external_scrape_forward == "ha" }
    "cluster"     = "[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]",
    "__replica__" = "alloy-[[ env "NOMAD_ALLOC_INDEX" ]]",
%{ endif }
    ${var.custom_external_labels}
  }
}
%{ endif }
[[ end ]]
EOF
      }

      # Sized for the OTLP relay plus the consul-SD scrape jobs and up to four
      # remote-write WALs. Calibrate with the alloy-monitor dashboard.
      resources {
        cpu    = 512
        memory = 1536
      }
    }
  }
}
