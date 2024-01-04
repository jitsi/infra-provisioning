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
      user = "root"
      driver = "docker"

      config {
        image = "prom/prometheus:latest"
        ports = ["prometheus_ui"]
        volumes = [
          "local/alerts.yml:/etc/prometheus/alerts.yml",
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

alerting:
  alertmanagers:
  - consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['alertmanager']

rule_files:
  - "alerts.yml"

scrape_configs:

  - job_name: 'alertmanager'
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['alertmanager']

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


  - job_name: 'prometheus'
    # Override the global default and scrape targets from this job every 5 seconds.
    scrape_interval: 5s

    static_configs:
      - targets: ['localhost:9090']


  - job_name: 'wavefront-proxy'

    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['wavefront-proxy']
EOH
    }

    template {
        change_mode = "noop"
        destination = "local/alerts.yml"
        data = <<EOH
---
groups:

- name: service_alerts
  rules:
  - alert: FabioDown
    expr: absent(up{job="fabio"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'fabio service is down in ${var.dc}'
      description: 'All fabio services are failing internal health checks. This means that traffic is not being forwarded to many services."
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

  - alert: LokiDown
    expr: absent(up{job="loki"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'loki service is down in ${var.dc}'
      description: 'All loki services are failing internal health checks. This means that no logs are being sent to Loki.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

  - alert: OscarDown
    expr: absent(up{job="oscar"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'oscar service is down in ${var.dc}'
      description: 'All oscar services are failing internal health checks. This means that synthetic probes are not running in this datacenter.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

  - alert: TelegrafDown
    expr: absent(up{job="telegraf"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'telegraf service is down in ${var.dc}'
      description: 'All telegraf services are failing internal health checks. This means that no metrics are being sent to wavefront-proxy or prometheus.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

  - alert: VectorDown
    expr: absent(up{job="vector"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'vector service is down in ${var.dc}'
      description: 'All vector services are failing internal health checks. This means that no logs are being sent to Loki.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

  - alert: WFProxyDown
    expr: absent(up{job="wavefront-proxy"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'wavefront-proxy service is down in ${var.dc}'
      description: 'All wavefront-proxy services are failing internal health checks. This means that no metrics are being sent to Wavefront.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'

- name: oscar_alerts
  rules:
  - alert: HAProxyRegionMismatch
    expr: jitsi_oscar_haproxy_region_mismatch < 1
    for: 1m
    labels:
      type: infra
      severity: critical
    annotations:
      summary: 'probe reached HAProxy in the incorrect region'
      description: 'An oscar probe to the domain has hit an haproxy outside of the local. This means that CloudFlare is not routing the request to the local region.'
      runbook: 'https://example.com/runbook-placeholder'
      dashboard: 'https://example.com/dashboard-placeholder'
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