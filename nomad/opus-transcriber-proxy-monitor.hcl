variable "dc" {
  type = string
}

variable "environment" {
  description = "Environment name; selects the Vault path secret/default/opus-transcriber-proxy/monitor-<environment> holding the CF Access service token"
  type        = string
}

variable "image" {
  description = "The opus-transcriber-proxy docker image (run in monitor mode via a command override)"
  type        = string
  default     = "jitsi/opus-transcriber-proxy:latest"
}

variable "pool_type" {
  description = "The type of pool to deploy to"
  type        = string
  default     = "general"
}

variable "metrics_port" {
  description = "Container port the synthetic metrics server listens on (mapped to a dynamic host port and scraped by Prometheus via Consul)"
  type        = number
  default     = 8080
}

variable "interval_seconds" {
  description = "How often the synthetic replays the sample against the endpoint"
  type        = string
  default     = "300"
}

variable "retry_delay_seconds" {
  description = "Seconds to wait before the single retry after a failed first attempt (the run reports failure only if both attempts fail)"
  type        = string
  default     = "20"
}

variable "ws_url_template" {
  description = "The wss:// /transcribe endpoint. The literal token __SESSION_ID__ is replaced at runtime with a fresh synthetic-<random> sessionId so successive runs never clash."
  type        = string
}

variable "sample_dump" {
  description = "Path (inside the image) to the JSONL Opus dump to replay"
  type        = string
  default     = "resources/sample.jsonl"
}

variable "connect_timeout" {
  description = "Seconds to wait for the websocket to open before failing (must cover a Cloudflare Container cold start, ~30s)"
  type        = string
  default     = "30"
}

variable "assert_min_finals" {
  description = "Minimum number of final transcripts required for the run to pass"
  type        = string
  default     = "1"
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"

  update {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  // docker driver requires linux
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "monitor" {
    constraint {
      attribute = "${meta.pool_type}"
      value     = var.pool_type
    }

    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "http" {
        to = var.metrics_port
      }
    }

    // The task is named "opus-transcriber-proxy" (not "...-monitor") on purpose: Nomad's Vault
    // policy grants a workload secret/data/default/<nomad_task>/*, so this name is what lets the
    // template below read secret/default/opus-transcriber-proxy/monitor-<environment>.
    task "opus-transcriber-proxy" {
      driver = "docker"

      // Nomad's Vault integration: lets the template below read the CF Access token from Vault.
      vault {
        change_mode = "noop"
      }

      // The opus-transcriber-proxy image run in monitor mode: it exposes /metrics with an
      // opus_transcriber_proxy_monitor_healthy flag and internally replays the sample dump
      // against the target /transcribe URL every interval, reporting unhealthy only after two
      // consecutive failed attempts. The default image CMD is the proxy; this overrides it.
      config {
        image   = var.image
        command = "node"
        args    = ["dist/bundle/monitor.js"]
        ports   = ["http"]
      }

      service {
        name = "opus-transcriber-proxy-monitor"
        port = "http"
        // Liveness only (process up) — a failing transcription must not restart the task.
        check {
          name     = "alive"
          type     = "http"
          path     = "/health"
          interval = "15s"
          timeout  = "3s"
        }
      }

      // Render MONITOR_HEADERS from the CF Access service token in Vault. The image's monitor mode
      // is generic (headers as a JSON object); the CF-Access header names live here, not in the
      // image. Single-quoted so the JSON's double quotes survive env-file parsing.
      template {
        data = <<EOF
MONITOR_HEADERS='{{ with secret "secret/default/opus-transcriber-proxy/monitor-${var.environment}" }}{"CF-Access-Client-Id":"{{ .Data.data.cf_access_client_id }}","CF-Access-Client-Secret":"{{ .Data.data.cf_access_client_secret }}"}{{ end }}'
EOF
        destination = "secrets/monitor.env"
        env         = true
      }

      env {
        MONITOR_PORT                = var.metrics_port
        MONITOR_URL                 = var.ws_url_template
        MONITOR_INTERVAL_SECONDS    = var.interval_seconds
        MONITOR_RETRY_DELAY_SECONDS = var.retry_delay_seconds
        MONITOR_CONNECT_TIMEOUT     = var.connect_timeout
        MONITOR_MIN_FINALS          = var.assert_min_finals
        MONITOR_SAMPLE              = var.sample_dump
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
