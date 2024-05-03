variable "dc" {
  type = string
}
variable "wavefront_instance" {
  type = string
  default = "metrics"
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

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    count = 2
    network {
      mode = "bridge"
      port "http" {
        to = 2878
      }
    }
    service {
      name = "wavefront-proxy"
      tags = ["int-urlprefix-${var.wavefront_proxy_hostname}/","int-urlprefix-${var.wavefront_proxy_hostname}:443/"]

      port = "http"

      connect {
        sidecar_service {}
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/status"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "wavefront-proxy" {
      vault {
        change_mode = "noop"
        
      }

      driver = "docker"
      env {
        WAVEFRONT_URL = "https://${var.wavefront_instance}.wavefront.com/api"
      }
      template {
        data = <<EOF
WAVEFRONT_TOKEN="{{ with secret "secret/default/wavefront-proxy/token" }}{{ .Data.data.api_token }}{{ end }}"
        EOF
        destination = "secrets/env"
        env = true
      }
      config {
        image = "wavefronthq/proxy:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
