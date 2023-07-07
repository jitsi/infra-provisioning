variable "dc" {
  type = string
}

variable "domain" {
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
      port "metrics" {
        to = 9313 
      }
    }

    // TODO: add constrict for meta.pool_type?

    task "ingress-cloudprober" {
      driver = "docker"
      user = "root"
      config {
        ports = ["metrics"]
        image = "cloudprober/cloudprober:latest"  // TODO: add cloudprober_version
        volumes = ["local/cloudprober.cfg:/etc/cloudprober.cfg"]
      }
      template {
          data = <<EOH
probe {
  name: "google_homepage"
  type: HTTP
  targets {
    host_names: "www.google.com"
  }
  interval_msec: 5000  # 5s
  timeout_msec: 1000   # 1s
}
probe {
  name: "domain_ingress"
  type: HTTP
  targets {
    host_names: "{{ env "var.domain" }}"
  }
  interval_msec: 5000  # 5s
  timeout_msec: 1000   # 1s
}
EOH
          destination = "local/cloudprober.cfg"
      }
      resources {
          cpu = 4000
          memory = 1024 
      }
      service {
        name = "oscar"
        tags = ["int-urlprefix-${var.oscar_hostname}/","ip-${attr.unique.network.ip-address}"]
        port = "oscar"
        tags = ["ip-${attr.unique.network.ip-address}"]
        check {
          name     = "oscar synthetics"
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
        