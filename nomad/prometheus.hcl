variable "dc" {
  type = string
}

variable "redis_ad" {
  type = string
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"

  # TODO: pick the availability domain based on where the volume is located
  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel = 1
    stagger      = "10s"
  }

  dynamic "group" {
    count = 1
    labels   = ["prometheus-${group.key}"]

    content {
      constraint {
        attribute  = "${meta.pool_type}"
        value     = "consul"
      }

      network {
        port "prometheus_ui" {
          static = 9090
        }
      }

      volume "prometheus" {
        type      = "host"
        read_only = false
        source    = "prometheus-${group.key}"
      }

      task "prometheus" {
        driver = "docker"

        config {
          image = "prom/prometheus:latest"
          ports = ["prometheus_ui"]
          volumes = [
            "local/prometheus.yml:/etc/prometheus/prometheus.yml"
          ]
        }

        volume_mount {
          volume      = "prometheus"
          destination = "/data"
          read_only   = false
        }

        template {
          change_mode = "noop"
          destination = "local/prometheus.yml"

          data = <<EOH
---
global:
  scrape_interval:     5s
  evaluation_interval: 5s

scrape_configs:

  - job_name: 'nomad_metrics'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['nomad-client', 'nomad']

    relabel_configs:
    - source_labels: ['__meta_consul_tags']
      regex: '(.*)http(.*)'
      action: keep

    scrape_interval: 5s
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
EOH
        }

        resources {
          cpu    = 500
          memory = 256
        }
        
        service {
          name = "prometheus"
          tags = ["urlprefix-/"]
          port = "prometheus_ui"

          check {
            name     = "prometheus_ui port alive"
            type     = "http"
            path     = "/-/healthy"
            interval = "10s"
            timeout  = "2s"
          }
        }
      }
    }
  }
}