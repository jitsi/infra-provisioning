variable "dc" {
  type = string
}

variable "oscar_hostname" {
  type = string
}

variable "domain" {
  type = string
}

variable "region" {
  type = string
}

variable "cloudprober_version" {
  type = string
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

  meta {
    cloudprober_version = "${var.cloudprober_version}"
  }

  group "synthetics" {

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

    // TODO: add constrict for meta.pool_type?

    task "ingress-cloudprober" {
      service {
        name = "oscar"
        tags = ["int-urlprefix-${var.oscar_hostname}/","ip-${attr.unique.network.ip-address}"]
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
probe {
  name: "local_ingress"
  type: HTTP
  targets {
    host_names: "${var.domain}"
  }
  interval_msec: 30000
  timeout_msec: 2000
}
probe {
  name: "haproxy_region"
  type: EXTERNAL
  targets {
    host_names: "${var.domain}"
  }
  external_probe {
    mode: ONCE 
    command: "/bin/oscar_probe.sh"
  }
  interval_msec: 30000
  timeout_msec: 2000
}
EOH
          destination = "local/cloudprober.cfg"
      }
      template {
        data = <<EOH
#!bin/sh

apk add python3
/usr/bin/python3 -m ensurepip --default-pip
/usr/bin/python3 -m pip install requests
/cloudprober --logtostderr
EOH
        destination = "local/custom_init.sh"
        perms = "755"
      }
      template {
        data = <<EOH
#!/bin/sh

DOMAIN=${var.domain} REGION=${var.region} /usr/bin/python3 /bin/oscar_probe.py
EOH
        destination = "local/oscar_probe.sh"
        perms = "755"
      }
      template {
        data = <<EOH
import requests
import os

url = 'https://' + os.environ['DOMAIN']
req = requests.get(url)

print("haproxy_region_check 1")

if req.headers['x-proxy-region'] != os.environ['REGION']:
    print("haproxy_region_check_failed 1")
else:
    print("haproxy_region_check_failed 0")
EOH
        destination = "local/oscar_probe.py"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/oscar_probe.sh:/bin/oscar_probe.sh",
          "local/oscar_probe.py:/bin/oscar_probe.py"
        ]
      }
      resources {
          cpu = 500
          memory = 256
      }
    }
  }
}
        