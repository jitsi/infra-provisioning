variable "dc" {
  type = string
}

variable "loki_mcp_hostname" {
  type = string
  default = "ops-prod-us-phoenix-1-loki-mcp.jitsi.net"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    auto_revert = false
    canary = 0
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "10m"
    unlimited      = true
  }

  group "loki-mcp" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay = "25s"
      mode = "delay"
    }

    constraint {
      attribute = "${meta.pool_type}"
      value     = "general"
    }

    network {
      port "http" {
        to = 3000
      }
    }

    task "loki-mcp" {
      driver = "docker"

      config {
        image = "ops-prod-us-phoenix-1-registry.jitsi.net/loki-mcp-server:0.6.0"
        force_pull = false
        ports = ["http"]
      }

      vault {
        change_mode = "noop"
      }

      env {
        # Default port for the MCP server
        PORT = "3000"
        LOKI_URL = "https://${meta.environment}-${meta.cloud_region}-loki.jitsi.net"
      }

#       template {
#         data = <<EOF
# {{ with secret "secret/default/loki-mcp/config" -}}
# LOKI_URL="{{ .Data.data.loki_url }}"
# LOKI_ORG_ID="{{ .Data.data.org_id }}"
# {{ end -}}
# {{ with secret "secret/default/loki-mcp/auth" -}}
# LOKI_USERNAME="{{ .Data.data.username }}"
# LOKI_PASSWORD="{{ .Data.data.password }}"
# LOKI_TOKEN="{{ .Data.data.token }}"
# {{ end -}}
# EOF
#         destination = "secrets/env"
#         env = true
#       }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "loki-mcp"
        tags = ["int-urlprefix-${var.loki_mcp_hostname}/"]
        port = "http"

        check {
          name     = "alive"
          type     = "tcp"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
