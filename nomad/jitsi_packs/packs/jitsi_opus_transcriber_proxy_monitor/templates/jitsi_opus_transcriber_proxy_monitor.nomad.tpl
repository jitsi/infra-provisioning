job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"

  update {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  reschedule {
    delay          = "30s"
    delay_function  = "exponential"
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
      value     = "[[ var "pool_type" . ]]"
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
        to = [[ var "metrics_port" . ]]
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
        image   = "[[ var "image" . ]]"
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
MONITOR_HEADERS='{{ with secret "secret/default/opus-transcriber-proxy/monitor-[[ var "environment" . ]]" }}{"CF-Access-Client-Id":"{{ .Data.data.cf_access_client_id }}","CF-Access-Client-Secret":"{{ .Data.data.cf_access_client_secret }}"}{{ end }}'
EOF
        destination = "secrets/monitor.env"
        env         = true
      }

      env {
        MONITOR_PORT                = "[[ var "metrics_port" . ]]"
        MONITOR_URL                 = "[[ var "ws_url_template" . ]]"
        MONITOR_INTERVAL_SECONDS    = "[[ var "interval_seconds" . ]]"
        MONITOR_RETRY_DELAY_SECONDS = "[[ var "retry_delay_seconds" . ]]"
        MONITOR_CONNECT_TIMEOUT     = "[[ var "connect_timeout" . ]]"
        MONITOR_MIN_FINALS          = "[[ var "assert_min_finals" . ]]"
        MONITOR_SAMPLE              = "[[ var "sample_dump" . ]]"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
