variable "dc" {
  type = string
}

variable "prometheus_hostname" {
  type = string
}

variable "prometheus_version" {
  type = string
  default = "v2.49.1"
}

variable "enable_remote_write" {
  type = string
  default = "false"
}

variable "remote_write_url" {
  type = string
  default = ""
}

variable "remote_write_username" {
  type = string
  default = ""
}

variable "remote_write_password" {
  type = string
  default = ""
}

variable "remote_write_org_id" {
  type = string
  default = ""
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

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
        image = "prom/prometheus:${var.prometheus_version}"
        force_pull = false
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

  external_labels:
    environment: '{{ env "meta.environment" }}'
    region: '{{ env "meta.cloud_region" }}'

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

  - job_name: 'consul'
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

  - job_name: 'nomad'
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

  - job_name: 'cloudprober'
    scrape_interval: 10s
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['cloudprober']

  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'telegraf'
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['telegraf']
    scrape_interval: 30s
    metrics_path: /metrics

  - job_name: 'wavefront-proxy'
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
      services: ['wavefront-proxy']

remote_write:
  - url: '${var.remote_write_url}'
    basic_auth:
      username: ${var.remote_write_username}
      password: ${var.remote_write_password}
    headers:
      X-Scope-OrgID: ${var.remote_write_org_id}
EOH
    }

    template {
        change_mode = "noop"
        destination = "local/alerts.yml"
        left_delimiter = "{{{"
        right_delimiter = "}}}"
        data = <<EOH
---
groups:

- name: service_alerts
  rules:
  - alert: ConsulDown
    expr: absent(up{job="consul"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: consul service is down in ${var.dc}
      description: All consul services are failing internal health checks in ${var.dc}. This means that service discovery is not functioning.
  - alert: NomadDown
    expr: absent(up{job="nomad"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: nomad service is down in ${var.dc}
      description: All nomad services are failing internal health checks in ${var.dc}. This means that service orchestration is not functioning.
  - alert: PrometheusDown
    expr: absent(up{job="prometheus"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: prometheus service is down in ${var.dc}
      description: All prometheus services are failing internal health checks in ${var.dc}. This means that metrics are not being stored and served.
  - alert: CloudproberDown
    expr: absent(up{job="cloudprober"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: cloudprober service is down in ${var.dc}
      description: Probe metrics from cloudprober are not being received in ${var.dc}. This means that data from synthetic probes is not being collected in this datacenter.
  - alert: TelegrafDown
    expr: prometheus_target_scrape_pools_total > sum(up{job="telegraf"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: telegraf services are down on some nodes in ${var.dc}
      description: telegraf is not running on all scraped nodes in ${var.dc}. This means that metrics for some services are not being collected.
  - alert: VectorDown
    expr: prometheus_target_scrape_pools_total > sum(up{job="vector"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: vector services are down on some nodes in ${var.dc}
      description: vector is not running on all scraped nodes in ${var.dc}. This means that logs for some services are not being collected.
  - alert: WFProxyDown
    expr: absent(up{job="wavefront-proxy"})
    for: 30s
    labels:
      type: infra
      severity: critical
    annotations:
      summary: wavefront-proxy service is down in ${var.dc}
      description: All wavefront-proxy services are failing internal health checks in ${var.dc}. This means that metrics are not being sent to Wavefront.

- name: cloudprober_alerts
  rules:
  - alert: ProbeUnhealthy
    expr: (5 * rate(cloudprober_failure{probe!="shard"}[5m]) > 0.2) or (5 * rate(cloudprober_timeouts{probe!="shard"}[5m]) > 0.2)
    for: 1m
    labels:
      type: infra
      severity: critical
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} is unhealthy
      description: The cloudprober {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: ShardUnhealthy
    expr: ((rate(cloudprober_failure{probe="shard"}[5m]) > 0) and on() count_over_time(rate(cloudprober_failure{probe="shard"}[5m])[5m:1m]) >= 5) or (rate(cloudprober_timeouts{probe="shard"}[5m]) > 0)
    for: 1m
    labels:
      type: infra
      severity: critical
    annotations:
      summary: shard {{ $labels.dst }} probe returned unhealthy from ${var.dc}
      description: An internal cloudprober probe from ${var.dc} to the {{ $labels.dst }} shard received an unhealthy response from signal-sidecar. This may be due to a variety of issues. If a local probe failed it is likely due to an unhealthy prosody or jicofo, if it's a remote probe then there may be a network issue between regions.
  - alert: HAProxyRegionMismatch
    expr: cloudprober_haproxy_region_mismatch < 1
    for: 1m
    labels:
      type: infra
      severity: severe 
    annotations:
      summary: a domain probe from ${var.dc} reached an haproxy outside the local region
      description: An cloudprober probe to the domain reached an haproxy outside of the local region. This means that CloudFlare may not be routing requests to ${var.dc}, likely due to failing health checks to the regional load balancer ingress.
EOH
    }

      resources {
        cpu    = 1000
        memory = 2048
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