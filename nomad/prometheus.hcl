variable "dc" {
  type = string
}

variable "prometheus_hostname" {
  type = string
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"

  update {
    max_parallel = 1
    stagger      = "10s"
  }

  group "prometheus" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "consul"
    }

    network {
      port "prometheus_ui" {
        to = 9090
      }
    }

    volume "prometheus" {
      type      = "host"
      read_only = false
      source    = "prometheus"
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
        destination = "/prometheus"
        read_only   = false
      }

      template {
        change_mode = "noop"
        destination = "local/prometheus.yml"

        data = <<EOH
---
global:
  scrape_interval:     10s
  evaluation_interval: 5s


scrape_configs:

  - job_name: 'consul_metrics'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['consul']

    relabel_configs:
    - source_labels: ['__address__']
      separator:     ':'
      regex:         '(.*):(8300)'
      target_label:  '__address__'
      replacement:   '$${1}:8500'

    metrics_path: /v1/agent/metrics
    params:
      format: ['prometheus']

  - job_name: 'nomad_metrics'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['nomad-clients', 'nomad-servers']

    relabel_configs:
    - source_labels: ['__address__']
      separator:     ':'
      regex:         '(.*):(4647)'
      target_label:  '__address__'
      replacement:   '$${1}:4646'

    - source_labels: ['__address__']
      separator:     ':'
      regex:         '(.*):(4648)'
      target_label:  '__address__'
      replacement:   '$${1}:4646'

    metrics_path: /v1/metrics
    params:
      format: ['prometheus']

  - job_name: 'telegraf_metrics'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['telegraf']

    scrape_interval:     30s
    metrics_path: /metrics


  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: 'prometheus'

    # Override the global default and scrape targets from this job every 5 seconds.
    scrape_interval: 5s

    static_configs:
      - targets: ['localhost:9090']
EOH
    }

      resources {
        cpu    = 500
        memory = 500
      }
        
      service {
        name = "prometheus"
        tags = ["int-urlprefix-${var.prometheus_hostname}/"]
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