variable "dc" {
  type = string
}

variable "ouroboros_hostname" {
  type = string
}

variable "ouroboros_version" {
  type = string
  default = "latest"
}

variable "ouroboros_count" {
  type = number
  default = 1
}

variable "headscale_url" {
  type = string
  description = "URL of the Headscale server"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 50

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "ouroboros" {
    count = var.ouroboros_count

    constraint {
      attribute  = "${meta.pool_type}"
      operator   = "set_contains_any"
      value      = "consul,general"
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    network {
      port "http" {
        to = 8080
      }
    }

    task "ouroboros" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "ouroboros/ouroboros:${var.ouroboros_version}"
        force_pull = false
        ports = ["http"]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
# Headscale connection
HEADSCALE_URL=${var.headscale_url}
{{ with secret "secret/default/headscale/api" }}
HEADSCALE_API_KEY={{ .Data.data.api_key }}
{{ end }}

# OIDC configuration for Okta
{{ with secret "secret/default/ouroboros/oidc" }}
OIDC_ISSUER={{ .Data.data.issuer }}
OIDC_CLIENT_ID={{ .Data.data.client_id }}
OIDC_CLIENT_SECRET={{ .Data.data.client_secret }}
{{ end }}
OIDC_REDIRECT_URL=https://${var.ouroboros_hostname}/auth/oidc/callback

# Application settings
BIND_ADDR=0.0.0.0:8080
LOG_LEVEL=info
BASE_URL=https://${var.ouroboros_hostname}

# Security settings
SESSION_SECRET={{ with secret "secret/default/ouroboros/session" }}{{ .Data.data.secret }}{{ end }}
CSRF_SECRET={{ with secret "secret/default/ouroboros/csrf" }}{{ .Data.data.secret }}{{ end }}

# Feature flags
ENABLE_OIDC=true
DISABLE_API_KEY_LOGIN=true
ALLOW_USER_REGISTRATION=false
EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "ouroboros"
        tags = ["int-urlprefix-${var.ouroboros_hostname}/"]
        port = "http"
        
        check {
          name     = "ouroboros-health"
          type     = "http"
          path     = "/health"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
