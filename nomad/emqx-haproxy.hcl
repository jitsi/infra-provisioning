variable "dc" {
  type = string
}

variable "domain" {
  type = string
  description = "Domain for HAProxy frontend"
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"
  priority    = 75

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "haproxy" {
    count = 3

    # All groups in this job should be scheduled on different hosts.
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    # Run on EMQX instance pool
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "emqx"
    }

    network {
      # MQTT ports
      port "mqtt" {
        static = 1883
      }
      port "mqtts" {
        static = 8883
      }

      # WebSocket ports
      port "ws" {
        static = 8083
      }
      port "wss" {
        static = 8084
      }

      # HAProxy admin interface
      port "admin" {
        static = 8080
      }
    }

    service {
      name = "emqx-haproxy"
      tags = [
        "urlprefix-${var.dc}-emqx-lb.${var.domain}/",
        "haproxy",
        "ip-${attr.unique.network.ip-address}"
      ]
      port = "mqtt"

      check {
        name     = "HAProxy health check"
        type     = "http"
        port     = "admin"
        path     = "/haproxy_health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "haproxy" {
      driver = "docker"

      config {
        image        = "haproxy:2.9"
        network_mode = "host"

        volumes = [
          "local/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg",
        ]
      }

      template {
        data = <<EOF
global
  log stdout format raw local0
  maxconn 50000
  daemon

defaults
  log  global
  mode tcp
  option tcplog
  option log-health-checks
  option dontlognull

  maxconn 50000
  retries  3
  timeout connect 10s
  timeout client  3m
  timeout server  3m
  timeout client-fin 50s
  timeout tunnel  1h

resolvers consul
    nameserver dns1 127.0.0.1:8600
    accepted_payload_size 8192
    hold valid 5s
    resolve_retries 3
    timeout resolve 1s
    timeout retry   1s

# HAProxy stats and health check endpoint
listen admin
  bind *:{{ env "NOMAD_PORT_admin" }}
  mode http
  monitor-uri /haproxy_health
  stats enable
  stats auth admin:admin
  stats uri /haproxy_stats
  stats refresh 10s

# MQTT TCP frontend (port 1883)
frontend mqtt-tcp
   bind *:{{ env "NOMAD_PORT_mqtt" }}
   mode tcp
   option tcplog
   default_backend emqx-mqtt-be

# MQTTS/TLS frontend (port 8883)
frontend mqtts-tcp
   bind *:{{ env "NOMAD_PORT_mqtts" }}
   mode tcp
   option tcplog
   default_backend emqx-mqtts-be

# WebSocket frontend (port 8083)
frontend ws-tcp
   bind *:{{ env "NOMAD_PORT_ws" }}
   mode tcp
   option tcplog
   default_backend emqx-ws-be

# WebSocket Secure frontend (port 8084)
frontend wss-tcp
   bind *:{{ env "NOMAD_PORT_wss" }}
   mode tcp
   option tcplog
   default_backend emqx-wss-be

# MQTT backend - load balance across all EMQX nodes
backend emqx-mqtt-be
    mode tcp
    balance leastconn
    option tcp-check
    # DNS-based service discovery via Consul
    server-template emqx 20 {{ env "meta.environment" }}.emqx.service.consul:1883 resolvers consul init-addr none check inter 10s fall 3 rise 2

# MQTTS backend
backend emqx-mqtts-be
    mode tcp
    balance leastconn
    option tcp-check
    server-template emqx 20 {{ env "meta.environment" }}.emqx.service.consul:8883 resolvers consul init-addr none check inter 10s fall 3 rise 2

# WebSocket backend
backend emqx-ws-be
    mode tcp
    balance leastconn
    option tcp-check
    server-template emqx 20 {{ env "meta.environment" }}.emqx.service.consul:8083 resolvers consul init-addr none check inter 10s fall 3 rise 2

# WebSocket Secure backend
backend emqx-wss-be
    mode tcp
    balance leastconn
    option tcp-check
    server-template emqx 20 {{ env "meta.environment" }}.emqx.service.consul:8084 resolvers consul init-addr none check inter 10s fall 3 rise 2
EOF

        destination = "local/haproxy.cfg"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
