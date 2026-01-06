variable "dc" {
  type = string
}

variable "tunnel_id" {
  type = string
}

variable "service_zone" {
  type = string
  default = "jitsi.net"
}

variable "cloudflare_zone" {
  type = string
  default = "cloudflare.jitsi.net"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "cloudflared" {
    count = 1

    constraint {
      attribute = "${meta.pool_type}"
      operator  = "set_contains_any"
      value     = "consul,general"
    }

    affinity {
      attribute = "${meta.pool_type}"
      value     = "general"
      weight    = 100
    }

    network {
      mode = "bridge"
      port "metrics" {
        to = 2000
      }
    }

    service {
      name = "cloudflared"
      tags = [
        "cloudflared",
        "tunnel"
      ]
      port = "metrics"

      check {
        name     = "ready"
        type     = "http"
        path     = "/ready"
        port     = "metrics"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "cloudflared" {
      driver = "docker"

      vault {
        change_mode = "noop"
      }

      # Cloudflared config with ingress rules
      template {
        data = <<EOF
tunnel: ${var.tunnel_id}
ingress:
  - hostname: ${var.dc}-loki.${var.cloudflare_zone}
    service: https://${var.dc}-loki.${var.service_zone}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
        destination = "local/config.yml"
        perms       = "644"
      }

      # Tunnel token from Vault
      template {
        data = <<EOF
{{- with secret "secret/default/cloudflared/${var.dc}" -}}
TUNNEL_TOKEN="{{ .Data.data.token }}"
{{- end -}}
EOF
        destination = "secrets/tunnel.env"
        env         = true
      }

      config {
        image = "cloudflare/cloudflared:latest"
        args = [
          "tunnel",
          "--config",
          "/etc/cloudflared/config.yml",
          "--metrics",
          "0.0.0.0:2000",
          "run",
          "--token",
          "${TUNNEL_TOKEN}"
        ]
        ports = ["metrics"]
        volumes = [
          "local/config.yml:/etc/cloudflared/config.yml"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
