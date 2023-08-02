variable "pool_type" {
  type = string
  default = "general"
}

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
  name: "ops-repo"
  type: HTTP
  targets {
    host_names: "ops-repo.jitsi.net"
  }
  interval_msec: 5000
  timeout_msec: 2000

  http_probe {
    protocol: HTTPS
    relative_url: "/health"
  }
}
EOH
          destination = "local/cloudprober.cfg"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
        ]
      }
      resources {
          cpu = 2000
          memory = 256
      }
    }
  }
}
        