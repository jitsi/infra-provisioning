variable "dc" {
  type = string
}
variable "grid" {
  type = string
}
variable "dns_zone" {
  type = string
  default = "jitsi.net"
}

variable "service_tag_urlprefix" {
  type = string
  default = "int-"
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "hub" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    count = 1

    network {
      port "http" {
        to = "4444"
      }

      port "publish" {
        to = "4442"
      }
      port "subscribe" {
        to = "4443"
      }
    }

    service {
      name = "grid-hub"
      tags = ["${var.service_tag_urlprefix}urlprefix-${var.dc}-${var.grid}-grid.${var.dns_zone}/","grid-${var.grid}"]
      port = "http"

      meta {
        publish_port = "${NOMAD_HOST_PORT_publish}"
        subscribe_port = "${NOMAD_HOST_PORT_subscribe}"
      }

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "hub" {
      driver = "docker"

      env {
        SE_HUB_HOST = "${attr.unique.network.ip-address}"
        SE_EVENT_BUS_HOST = "${attr.unique.network.ip-address}"
        SE_NODE_HOST = "${attr.unique.network.ip-address}"
      }

      config {
        image        = "selenium/hub:latest"
        ports = ["http","publish","subscribe"]
      }
      resources {
        cpu    = 4000
        memory = 2048
      }
    }
  }
}
