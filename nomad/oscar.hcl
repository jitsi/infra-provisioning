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

    // add constrict for meta.pool_type?

    task "ingress-cloudprober" {
      driver = "docker"
      user = "root"
      config {
        ports = ["metrics"]
        image = "cloudprober/cloudprober:latest"  // add cloudprober_version
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
EOH
          destination = "local/cloudprober.cfg"
      }
      resources {
          cpu = 8000
          memory = 2048 
      }
    }
  }
}
        