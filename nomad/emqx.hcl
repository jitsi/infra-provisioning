variable "dc" {
  type = string
}

variable "emqx_version" {
  type = string
  default = "5.8.3"
}

variable "emqx_count" {
  type = number
  default = 3
  description = "Number of EMQX nodes in the cluster"
}

variable "emqx_cluster_cookie" {
  type = string
  default = "emqx_secret_cookie"
  description = "Erlang cookie for cluster authentication"
}

variable "domain" {
  type = string
  description = "Domain for dashboard access"
}

locals {
  emqx_nodes = range(var.emqx_count)
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    stagger           = "30s"
  }

  dynamic "group" {
    for_each = local.emqx_nodes
    labels   = ["emqx-${group.key}"]
    content {
      count = 1

      constraint {
        attribute  = "${meta.pool_type}"
        value     = "emqx"
      }

      constraint {
        attribute  = "${meta.group-index}"
        value     = "${group.key}"
      }

      restart {
        attempts = 3
        interval = "5m"
        delay    = "30s"
        mode     = "delay"
      }

      network {
        mode = "host"

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

        # Dashboard
        port "dashboard" {
          static = 18083
        }

        # Cluster ports
        port "ekka" {
          static = 4370
        }
        port "cluster_rpc" {
          static = 5370
        }
      }

      volume "emqx" {
        type      = "host"
        read_only = false
        source    = "emqx-${group.key}"
      }

      task "emqx" {
        driver = "docker"
        user = "root"

        config {
          network_mode = "host"
          image = "emqx/emqx:${var.emqx_version}"
          ports = ["mqtt", "mqtts", "ws", "wss", "dashboard", "ekka", "cluster_rpc"]
        }

        volume_mount {
          volume      = "emqx"
          destination = "/opt/emqx/data"
          read_only   = false
        }

        env {
          # Node name and cookie for Erlang clustering
          EMQX_NODE__NAME = "emqx@${NOMAD_IP_ekka}"
          EMQX_NODE__COOKIE = "${var.emqx_cluster_cookie}"

          # Cluster discovery via DNS (Consul service)
          EMQX_CLUSTER__DISCOVERY_STRATEGY = "dns"
          EMQX_CLUSTER__DNS__NAME = "emqx.service.${var.dc}.consul"
          EMQX_CLUSTER__DNS__RECORD_TYPE = "a"

          # Listener configuration
          EMQX_LISTENERS__TCP__DEFAULT__BIND = "0.0.0.0:1883"
          EMQX_LISTENERS__SSL__DEFAULT__BIND = "0.0.0.0:8883"
          EMQX_LISTENERS__WS__DEFAULT__BIND = "0.0.0.0:8083"
          EMQX_LISTENERS__WSS__DEFAULT__BIND = "0.0.0.0:8084"

          # Dashboard
          EMQX_DASHBOARD__LISTENERS__HTTP__BIND = "0.0.0.0:18083"

          # Cluster RPC port
          EMQX_RPC__PORT_DISCOVERY = "manual"
          EMQX_RPC__TCP_SERVER_PORT = "5370"
          EMQX_RPC__TCP_CLIENT_NUM = "10"
        }

        resources {
          cpu    = 2000
          memory = 4096
        }

        # MQTT TCP port service
        service {
          name = "emqx"
          port = "mqtt"
          tags = [
            "emqx-${group.key}",
            "mqtt",
            "ip-${attr.unique.network.ip-address}",
            "domain-${var.domain}"
          ]

          meta {
            node_index = "${group.key}"
            version = "${var.emqx_version}"
            protocol = "mqtt"
          }

          check {
            name     = "EMQX MQTT port alive"
            type     = "tcp"
            interval = "10s"
            timeout  = "2s"
          }
        }

        # MQTTS (TLS) service
        service {
          name = "emqx-tls"
          port = "mqtts"
          tags = [
            "emqx-${group.key}",
            "mqtts",
            "ip-${attr.unique.network.ip-address}"
          ]

          meta {
            node_index = "${group.key}"
            protocol = "mqtts"
          }

          check {
            name     = "EMQX MQTTS port alive"
            type     = "tcp"
            interval = "10s"
            timeout  = "2s"
          }
        }

        # WebSocket service
        service {
          name = "emqx-ws"
          port = "ws"
          tags = [
            "emqx-${group.key}",
            "websocket",
            "ip-${attr.unique.network.ip-address}"
          ]

          meta {
            node_index = "${group.key}"
            protocol = "ws"
          }

          check {
            name     = "EMQX WebSocket port alive"
            type     = "tcp"
            interval = "10s"
            timeout  = "2s"
          }
        }

        # Dashboard service
        service {
          name = "emqx-dashboard"
          port = "dashboard"
          tags = [
            "int-urlprefix-emqx.${var.domain}/",
            "emqx-${group.key}",
            "ip-${attr.unique.network.ip-address}"
          ]

          meta {
            node_index = "${group.key}"
          }

          check {
            name     = "EMQX Dashboard health"
            type     = "http"
            path     = "/api/v5/status"
            interval = "10s"
            timeout  = "2s"
          }
        }

        # Prometheus metrics service
        service {
          name = "emqx-metrics"
          port = "dashboard"
          tags = [
            "prometheus",
            "emqx-${group.key}",
            "ip-${attr.unique.network.ip-address}"
          ]

          meta {
            node_index = "${group.key}"
            metrics_path = "/api/v5/prometheus/stats"
          }

          check {
            name     = "EMQX Metrics endpoint"
            type     = "http"
            path     = "/api/v5/prometheus/stats"
            interval = "30s"
            timeout  = "5s"
          }
        }
      }
    }
  }
}
