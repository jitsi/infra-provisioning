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
    default = "star_example_com"
}

variable "coturn_version" {
    type = string
    # Conservative fallback: the version the fleet already runs. Environments
    # move forward by setting coturn_version in their vars.yml, so a config
    # lookup that comes back empty can never drag an environment onto a new
    # coturn by surprise. Pin the -rN docker tag rather than the bare "4.18.0"
    # when moving up: the bare tag is re-pushed on every debian base rebuild.
    default = "4.6.3"
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "system"


  update {
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    progress_deadline = "10m"
    auto_revert = true
  }

  group "coturn" {
    count = 1

    restart {
      attempts = 3
      delay    = "25s"
      interval = "5m"
      mode = "delay"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "coturn"
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
      vault {
        change_mode = "noop"

      }
      driver = "docker"
      user = "root"
      config {
        network_mode = "host"
        image = "coturn/coturn:${var.coturn_version}"
        args = [
          "-c",
          "/local/coturn.conf",
        ]
        ports = ["coturn","metrics"]
        volumes = ["local/coturn.conf:/local/coturn.conf"]
      }
      template {
        data = <<EOH
# This file has to be valid for BOTH coturn versions in flight, because
# coturn_version is set per environment while the fleet rolls forward. Each
# side logs a complaint about the other side's lines and ignores them, which
# is cosmetic; getting the set wrong is not. Verified against both images.
#
# Load-bearing on 4.6.3, redundant on 4.18 (where each is already the
# default). Do NOT drop these until every environment is on 4.18: on 4.6.3
# removing no-rfc5780 alone silently turns NAT behaviour discovery back on.
# On 4.18 the first three are accepted and the last three warn "Bad
# configuration format" and are ignored.
no-cli
no-rfc5780
no-software-attribute
no-stun-backward-compatibility
no-tlsv1
no-tlsv1_1
#
# 4.18 additionally stops starting DTLS listeners unless --dtls is passed,
# which is why there is no no-dtls line: not asking for it is the mitigation.
use-auth-secret
# Both versions accept this; it is the non-deprecated spelling of the
# keep-address-family flag this replaced.
allocation-default-address-family=keep
no-multicast-peers
no-tcp-relay
# Log to the task's stdout so nomad collects the lines. Without this coturn
# writes ~54 lines to stdout and then switches to a file inside the container
# that nothing collects. Per-session and per-packet logging stays off because
# --verbose is not set, so this is startup and rare-event output only.
log-file=stdout
# The two below are 4.18-only and warn "Bad configuration format" on 4.6.3.
log-min-level=info
# Cap UDP 401 Unauthorized responses per source IP. Without this an attacker
# who spoofs a victim's source address bounces amplified 401s at them.
# Authenticated relay traffic never reaches the 401 branch and is unaffected.
unauthorized-ratelimit
# https://ssl-config.mozilla.org/#server=haproxy&version=2.1&config=intermediate&openssl=1.1.0g&guideline=5.4
cipher-list=ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
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
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
static-auth-secret=${var.coturn_auth_secret}
realm=${var.coturn_realm}
listening-port=443
prometheus
cert=/secrets/ssl.crt
pkey=/secrets/ssl.key
external-ip={{ env "meta.public_ip" }}/{{ env "attr.unique.network.ip-address" }}
relay-ip={{ env "attr.unique.network.ip-address" }}
EOH
        destination = "local/coturn.conf"
      }

      template {
        data = <<EOF
{{- with secret "secret/ssl/${var.ssl_cert_name}/cert" }}{{ .Data.data.cert }}{{ .Data.data.chain }}{{ end -}}
EOF
        destination = "secrets/ssl.crt"
        # coturn re-reads cert and key from disk on SIGUSR2, so a rotation in
        # vault takes effect without a redeploy. A reload that catches the pair
        # mid-rotation logs an error and keeps the running context; the signal
        # from the other template then completes it.
        change_mode = "signal"
        change_signal = "SIGUSR2"
      }

      template {
        data = <<EOF
{{- with secret "secret/ssl/${var.ssl_cert_name}/cert" }}{{ .Data.data.key }}{{ end -}}
EOF
        destination = "secrets/ssl.key"
        change_mode = "signal"
        change_signal = "SIGUSR2"
      }

      resources {
        cpu    = 10000
        memory = 15000
      }
      shutdown_delay = "5s"
      service {
        name = "coturn"
        port = "coturn"
        tags = ["ip-${attr.unique.network.ip-address}"]
        meta {
          public_ip = "${meta.public_ip}"
        }
        check {
          name     = "coturn healthcheck"
          port     = "metrics"
          type     = "http"
          path     = "/metrics"
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
