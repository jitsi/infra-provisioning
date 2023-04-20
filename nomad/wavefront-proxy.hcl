variable "dc" {
  type = string
}
variable "wavefront_instance" {
  type = string
  default = "metrics"
}
variable "wavefront_token" {
  type = string
}
variable "wavefront_proxy_hostname" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type = "service"

  group "wavefront-proxy" {
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    count = 2
    network {
      port "http" {
        to = 2878
      }
    }
    task "wavefront-proxy" {
      service {
        name = "wavefront-proxy"
        tags = ["int-urlprefix-${var.wavefront_proxy_hostname}/","int-urlprefix-${var.wavefront_proxy_hostname}:443/"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      env {
        WAVEFRONT_URL = "https://${var.wavefront_instance}.wavefront.com/api"
        WAVEFRONT_TOKEN = "${var.wavefront_token}"
      }
      config {
        image = "wavefronthq/proxy:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
