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

# assumes "dev", "stage", or "prod"
variable "environment_type" {
  type = string
  default = "dev"
}

variable "default_service_name" {
  type = string
  default = "default"
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
    datacenter: '${var.dc}'
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
  - alert: AlertmanagerDown
    expr: absent(up{job="alertmanager"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: alertmanager service is down in ${var.dc}
      description: Metrics from alertmanager are not being received in ${var.dc}. This means that alerts are not being emitted from the datacenter. Thus, the fact that you received an alert from this datacenter is quite curious indeed.
  - alert: CloudproberDown
    expr: absent(up{job="cloudprober"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: cloudprober service is down in ${var.dc}
      description: Metrics from cloudprober are not being received in ${var.dc}. This means that data from synthetic probes is not being collected or alerted on in this datacenter.
  - alert: ConsulDown
    expr: absent(up{job="consul"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: consul service is down in ${var.dc}
      description: No consul services are emitting metrics in ${var.dc}. This may mean that service discovery is not functioning.
  - alert: NomadDown
    expr: absent(up{job="nomad"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: nomad service is down in ${var.dc}
      description: No nomad services are emitting metrics in ${var.dc}. This may mean that service orchestration is not functioning.
  - alert: PrometheusDown
    expr: absent(up{job="prometheus"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: prometheus service is down in ${var.dc}
      description: No prometheus services are emitting metrics in ${var.dc}. This may mean that no metrics are being stored or served.
  - alert: TelegrafDown
    expr: sum(prometheus_target_scrape_pools_total) > (sum(up{job="telegraf"}) or vector(0))
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: telegraf services are down on some nodes in ${var.dc}
      description: telegraf metrics are not being emitted from all nodes in ${var.dc}. This means that metrics for some services are not being collected.
  - alert: WFProxyDown
    expr: absent(up{job="wavefront-proxy"})
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: wavefront-proxy service is down in ${var.dc}
      description: wavefront-proxy metrics are not being collected in ${var.dc}. This means that metrics from this datacenter may not being sent to Wavefront.

- name: cloudprober_alerts
  rules:
  - alert: ProbeUnhealthy
    expr: (cloudprober_failure{probe!="shard"} > 0) or (cloudprober_timeouts{probe!="shard"} > 0)
    for: 2m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: warning
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: ProbeUnhealthy
    expr: (cloudprober_failure{probe!="shard"} > 0) or (cloudprober_timeouts{probe!="shard"} > 0)
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: ShardUnhealthy
    expr: ((cloudprober_failure{probe="shard"} > 0) and on() count_over_time(cloudprober_failure{probe="shard"}[5m:1m]) > 5) or (cloudprober_timeouts{probe="shard"} > 0)
    for: 2m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: shard {{ $labels.dst }} probe returned failed or timed-out from ${var.dc}
      description: An internal probe from ${var.dc} to the {{ $labels.dst }} shard timed-out or received an unhealthy response from signal-sidecar. This may be due to a variety of issues. If a local probe failed it is likely due to an unhealthy prosody or jicofo, if it's a remote probe then there may be a network issue between regions.
  - alert: HAProxyRegionMismatch
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 2m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: warning
    annotations:
      summary: a domain probe from ${var.dc} reached an haproxy outside the local region
      description: An cloudprober probe to the domain reached an haproxy outside of the local region. This means that CloudFlare may not be routing requests to ${var.dc}, likely due to failing health checks to the regional load balancer ingress.
  - alert: HAProxyRegionMismatch
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 10m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: a domain probe from ${var.dc} reached an haproxy outside the local region
      description: An cloudprober probe to the domain reached an haproxy outside of the local region. This means that CloudFlare may not be routing requests to ${var.dc}, likely due to failing health checks to the regional load balancer ingress.
  - alert: LatencyHigh
    expr: (cloudprober_latency{probe="latency"} > 500) or (cloudprober_latency{probe="latency_https"} > 500)
    for: 2m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: warning
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has high latency
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} has had high latency for 2 minutes, most recently at {{ $value }} ms.
  - alert: LatencyHigh
    expr: (cloudprober_latency{probe="latency"} > 1000) or (cloudprober_latency{probe="latency_https"} > 1000)
    for: 5m
    labels:
      environment_type: "{{ if $labels.environment_type }}{{ $labels.environment_type }}{{ else }}${var.environment_type}{{ end }}"
      service: "{{ if $labels.service }}{{ $labels.service }}{{ else }}${var.default_service_name}{{ end }}"
      severity: critical
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has extremely high latency
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} has extremely high latency for 5 minutes, most recently at {{ $value }} ms.
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