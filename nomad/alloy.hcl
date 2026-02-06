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
      port "http" {
        to = 12345
      }
    }

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

    task "alloy" {
      driver = "docker"

      config {
        image = "grafana/alloy:latest"
        args  = [
          "run",
          "/etc/alloy/config.alloy",
          "--server.http.listen-addr=0.0.0.0:12345"
        ]
        ports = ["otlp-grpc", "otlp-http", "http"]
        volumes = [
          "local/config.alloy:/etc/alloy/config.alloy"
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
    logs    = [otelcol.exporter.otlphttp.loki.input]
    metrics = [otelcol.exporter.prometheus.default.input]
    traces  = [otelcol.exporter.otlphttp.tempo.input]
  }
}

prometheus.exporter.self "self" {}

// Configure a prometheus.scrape component to collect Alloy metrics.
prometheus.scrape "demo" {
  targets    = prometheus.exporter.self.self.targets
  forward_to = [prometheus.remote_write.default.receiver]
}

// Export logs to Loki via internal LB (DNS routes through OCI internal LB -> Fabio)
// Loki's OTLP endpoint is at /otlp
otelcol.exporter.otlphttp "loki" {
  client {
    endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}/otlp"
  }
}

// Export traces to Tempo via internal LB
otelcol.exporter.otlphttp "tempo" {
  client {
    endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-tempo.${var.top_level_domain}"
  }
}

// Export metrics to Prometheus via remote write through internal LB
otelcol.exporter.prometheus "default" {
  forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
  endpoint {
    url = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-prometheus.${var.top_level_domain}/api/v1/write"
  }
}
EOF
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }
}
