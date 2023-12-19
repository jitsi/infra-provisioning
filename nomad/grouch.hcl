variable "pool_type" {
  type = string
  default = "general"
}

variable "dc" {
  type = string
}

variable "grouch_hostname" {
  type = string
}

variable "domain" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "top_level_domain" {
  type = string
  default = "jitsi.net"
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = [var.dc]
  type = "service"

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

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "synthetics" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
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
        to = 9313 
      }
    }
    task "websocket-monitor" {
      service {
        name = "grouch"
        tags = ["int-urlprefix-${var.grouch_hostname}/","ip-${attr.unique.network.ip-address}"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      template {
        data = <<EOH
import requests
import os

url = 'https://' + os.environ['DOMAIN'] + "/about/health"
req = requests.get(url)

if req.headers['x-proxy-region'] == os.environ['REGION']:
    print("haproxy_region_check_passed 1")
else:
    print("haproxy_region_check_passed 0")
EOH
        destination = "local/grouch-websocket.py"
      }
            template {
        data = <<EOH
#!bin/sh

apk add python3 curl
/usr/bin/python3 -m ensurepip --default-pip
/usr/bin/python3 -m pip install requests
/usr/bin/python3 /bin/grouch-websocket.py
EOH
        destination = "local/custom_init.sh"
        perms = "755"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/grouch-websocket.py:/bin/grouch-websocket.py",
        ]
      }
      resources {
          cpu = 2000
          memory = 256
      }
    }
  }
}
