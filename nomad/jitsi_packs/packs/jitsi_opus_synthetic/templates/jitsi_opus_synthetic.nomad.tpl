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

  group "synthetic" {
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

    task "opus-synthetic" {
      driver = "docker"

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
        name = "opus-synthetic"
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

      env {
        MONITOR_PORT                = "[[ var "metrics_port" . ]]"
        MONITOR_URL                 = "[[ var "ws_url_template" . ]]"
        MONITOR_INTERVAL_SECONDS    = "[[ var "interval_seconds" . ]]"
        MONITOR_RETRY_DELAY_SECONDS = "[[ var "retry_delay_seconds" . ]]"
        MONITOR_CONNECT_TIMEOUT     = "[[ var "connect_timeout" . ]]"
        MONITOR_MIN_FINALS          = "[[ var "assert_min_finals" . ]]"
        MONITOR_SAMPLE              = "[[ var "sample_dump" . ]]"
        // The image's monitor mode takes headers as a generic JSON object; the CF Access service
        // token is passed here (it is what gates the endpoint) without the image knowing anything
        // CF-specific.
        MONITOR_HEADERS = "{\"CF-Access-Client-Id\":\"[[ var "cf_access_client_id" . ]]\",\"CF-Access-Client-Secret\":\"[[ var "cf_access_client_secret" . ]]\"}"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
