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

variable wavefront_enabled {
  type = bool
  default = false
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
      port "http" {
        to = 2878
      }
    }
    task "wavefront-proxy" {
      vault {
        change_mode = "noop"
        
      }
      service {
        name = "wavefront-proxy"
        tags = ["int-urlprefix-${var.wavefront_proxy_hostname}/","int-urlprefix-${var.wavefront_proxy_hostname}:443/"]

        port = "http"

        check {
          name     = "alive"
          type     = "http"
          path     = "/status"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      env {
        WAVEFRONT_URL = "https://${var.wavefront_instance}.wavefront.com/api"
        WAVEFRONT_PROXY_ARGS="--preprocessorConfigFile /etc/wavefront/wavefront-proxy/preprocessor_rules.yaml"
      }
      template {
        data = <<EOF
'2878':
  - rule   : block-loki-stats
    action : block
    scope  : metricName
    match  : "loki\\..*"
  - rule   : block-cloudprober
    action : block
    scope  : metricName
    match  : "cloudprober\\..*"
%{ if !var.wavefront_enabled }
  - rule   : block-all
    action : block
    scope  : metricName
    match  : ".*"
%{ endif }
EOF
        destination = "local/preprocessor_rules.yaml"
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
        volumes = [
          "local/preprocessor_rules.yaml:/etc/wavefront/wavefront-proxy/preprocessor_rules.yaml",
        ]
      }

      resources {
        cpu    = 512
        memory = 1024
      }
    }
  }
}
