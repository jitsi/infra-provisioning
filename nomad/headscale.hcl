variable "dc" {
  type = string
}

variable "headscale_hostname" {
  type = string
}

variable "headscale_version" {
  type = string
  default = "latest"
}

variable "headscale_count" {
  type = number
  default = 1
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 50

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "headscale" {
    count = var.headscale_count

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
      size = 1000
    }

    network {
      port "http" {
        to = 8080
      }
      port "grpc" {
        to = 50443
      }
      port "metrics" {
        to = 9090
      }
    }

    task "headscale" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "headscale/headscale:${var.headscale_version}"
        force_pull = false
        ports = ["http", "grpc", "metrics"]
        volumes = [
          "local/config.yaml:/etc/headscale/config.yaml",
          "alloc/data:/var/lib/headscale"
        ]
        command = "serve"
      }

      template {
        destination = "local/config.yaml"
        data = <<EOF
server_url: https://${var.headscale_hostname}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: false

private_key_path: /var/lib/headscale/private.key
noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v6: fd7a:115c:a1e0::/48
  v4: 100.64.0.0/10

derp:
  server:
    enabled: false

  urls:
    - https://controlplane.tailscale.com/derpmap/default

  auto_update_enabled: true
  update_frequency: 24h

disable_check_updates: false

ephemeral_node_inactivity_timeout: 30m

node_update_check_interval: 10s

database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite

acme_url: https://acme-v02.api.letsencrypt.org/directory
acme_email: ""

tls_letsencrypt_hostname: ""
tls_cert_path: ""
tls_key_path: ""

log:
  format: text
  level: info

oidc:
  only_start_if_oidc_is_available: false
  issuer: ""
  client_id: ""
  client_secret_path: ""
  scope: ["openid", "profile", "email"]
  extra_params: {}
  allowed_domains: []
  allowed_users: []
  allowed_groups: []

logtail:
  enabled: false

randomize_client_port: false

dns:
  override_local_dns: true
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8
  search_domains: []
  magic_dns: true
  base_domain: "headscale.local"
EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "headscale"
        tags = ["int-urlprefix-${var.headscale_hostname}/"]
        port = "http"
        
        check {
          name     = "headscale-health"
          type     = "http"
          path     = "/health"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "headscale-grpc"
        port = "grpc"
        tags = ["headscale-grpc"]
      }

      service {
        name = "headscale-metrics"
        port = "metrics"
        tags = ["headscale-metrics"]
      }
    }
  }
}
