variable "dc" {
  type = string
}

variable "coturn_realm" {
  type = string
  default = "coturn.jitsi.net"
}

variable "coturn_auth_secret" {
    type = string
    default = "changeme"
}

variable "ssl_cert_name" {
    type = string
    default = "secret_key_file"
}

variable "coturn_count" {
    type = number
    default = 2
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  group "coturn" {
    count = var.coturn_count

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "coturn"
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    volume "ssl" {
      type      = "host"
      read_only = true
      source    = "ssl"
    }
    network {
      port "coturn" {
        static = 443
      }
      port "metrics" {
        static = 9641
      }
    }
    task "coturn" {
      driver = "docker"
      user = "root"
      config {
        network_mode = "host"
        image = "coturn/coturn"
        args = [
          "-c",
          "/local/coturn.conf",
        ]
        ports = ["coturn"]
        volumes = ["local/coturn.conf:/local/coturn.conf"]
      }
      volume_mount {
        volume      = "ssl"
        destination = "/etc/ssl"
        read_only   = true
      }
      template {
        data = <<EOH
use-auth-secret
keep-address-family
no-multicast-peers
no-cli
no-tcp-relay
no-tlsv1
no-tlsv1_1
# https://ssl-config.mozilla.org/#server=haproxy&version=2.1&config=intermediate&openssl=1.1.0g&guideline=5.4
cipher-list=ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.0.2.0-192.0.2.255
denied-peer-ip=192.88.99.0-192.88.99.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=198.51.100.0-198.51.100.255
denied-peer-ip=203.0.113.0-203.0.113.255
denied-peer-ip=240.0.0.0-255.255.255.255
denied-peer-ip=::1
denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-feaf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
static-auth-secret=${var.coturn_auth_secret}
realm=${var.coturn_realm}
listening-port=443
prometheus
cert=/etc/ssl/${var.ssl_cert_name}.crt
pkey=/etc/ssl/${var.ssl_cert_name}.key
external-ip={{ env "meta.public_ip" }}/{{ env "attr.unique.network.ip-address" }}
relay-ip={{ env "attr.unique.network.ip-address" }}
EOH
        destination = "local/coturn.conf"
      }
      resources {
        cpu    = 10000
        memory = 15360
      }
      service {
        name = "coturn"
        port = "coturn"
        tags = ["ip-${attr.unique.network.ip-address}"]
        meta {
          public_address = ${meta.public_ip}
        }
        check {
          name     = "coturn healthcheck"
          port     = "metrics"
          type     = "http"
          path     = "/"
          interval = "20s"
          timeout  = "5s"
          check_restart {
            limit           = 3
            grace           = "60s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}