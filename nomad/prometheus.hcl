variable "dc" {
  type = string
}

variable "prometheus_hostname" {
  type = string
}

variable "prometheus_version" {
  type = string
  default = "v2.54.1"
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
- name: infra_service_alerts
  rules:
  - alert: Alertmanager_Down
    expr: absent(up{job="alertmanager"})
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: alertmanager service is down in ${var.dc}
      description: Metrics from alertmanager are not being received in ${var.dc}. This means that alerts are not being emitted from the datacenter. Thus, the fact that you received an alert from this datacenter is quite curious indeed.
  - alert: Cloudprober_Down
    expr: absent(up{job="cloudprober"})
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: cloudprober service is down in ${var.dc}
      description: Metrics from cloudprober are not being received in ${var.dc}. This means that data from synthetic probes is not being collected or alerted on in this datacenter.
  - alert: Consul_Down
    expr: count(consul_server_isLeader) < 3
    for: 5m
    labels:
      service: infra
      severity: warning
    annotations:
      summary: there are fewer than 3 consul servers in ${var.dc}
      description: There are fewer than 3 consul servers in ${var.dc}, which means the cluster is not complete. This may mean that service discovery may not be functioning. Currently there are {{ $value }} servers.
  - alert: Consul_Down
    expr: absent(consul_server_isLeader)
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: the consul cluster is down in ${var.dc}
      description: The consul cluster in ${var.dc} is not emitting metrics and may be entirely down. This may mean that service discovery may not be functioning and all service may be compromised.
  - alert: Nomad_Down
    expr: count(nomad_runtime_alloc_bytes) < 3
    for: 5m
    labels:
      service: infra
      severity: warning
    annotations:
      summary: nomad service is compromised in ${var.dc}
      description: There are fewer than 3 nomad clients emitting metrics in ${var.dc}. This may mean that service orchestration and job placement are not functioning.
  - alert: Nomad_Down
    expr: absent(nomad_runtime_alloc_bytes)
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: nomad service is completely down in ${var.dc}
      description: No nomad clients are emitting metrics in ${var.dc}. This may mean that service orchestration and job placement are not functioning.
  - alert: Prometheus_Down
    expr: absent(up{job="prometheus"})
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: prometheus service is down in ${var.dc}
      description: No prometheus services are emitting metrics in ${var.dc}. This may mean that no metrics are being stored or served.
  - alert: Telegraf_Down
    expr: nomad_nomad_heartbeat_active > (sum(up{job="telegraf"}) or vector(0))
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: telegraf services are down on some nodes in ${var.dc}
      description: telegraf metrics are not being emitted from all nodes in ${var.dc}. This means that metrics for some services are not being collected.

- name: cloudprober_alerts
  rules:
  - alert: Probe_Infra_Unhealthy
    expr: (cloudprober_failure{probe!="shard",service="infra"} > 0) or (cloudprober_timeouts{probe!="shard",service="infra"} > 0)
    for: 2m
    labels:
      service: infra
      severity: warning
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: Probe_Infra_Unhealthy
    expr: (cloudprober_failure{probe!="shard",service="infra"} > 0) or (cloudprober_timeouts{probe!="shard",service="infra"} > 0)
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: Probe_Jitsi_Unhealthy
    expr: (cloudprober_failure{probe!="shard",service="jitsi"} > 0) or (cloudprober_timeouts{probe!="shard",service="jitsi"} > 0)
    for: 2m
    labels:
      service: jitsi
      severity: warning
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: Probe_Jitsi_Unhealthy
    expr: (cloudprober_failure{probe!="shard",service="jitsi"} > 0) or (cloudprober_timeouts{probe!="shard",service="jitsi"} > 0)
    for: 5m
    labels:
      service: jitsi
      severity: critical
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} timed-out or is unhealthy"
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} timed-out or received an unhealthy response.
  - alert: Probe_Shard_Unhealthy
    expr: ((cloudprober_failure{probe="shard"} > 0) and on() count_over_time(cloudprober_failure{probe="shard"}[5m:1m]) > 5) or (cloudprober_timeouts{probe="shard"} > 0)
    for: 2m
    labels:
      service: jitsi
      severity: critical
    annotations:
      summary: shard {{ $labels.dst }} probe returned failed or timed-out from ${var.dc}
      description: An internal probe from ${var.dc} to the {{ $labels.dst }} shard timed-out or received an unhealthy response from signal-sidecar. This may be due to a variety of issues. If a local probe failed it is likely due to an unhealthy prosody or jicofo, if it's a remote probe then there may be a network issue between regions.
  - alert: Probe_Ingress_Region_Unhealthy
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 2m
    labels:
      service: infra
      severity: warning
    annotations:
      summary: a domain probe from ${var.dc} reached an haproxy outside the local region
      description: A cloudprober probe to the domain reached an haproxy outside of the local region. This means that cloudflare may not be routing requests to ${var.dc}, likely due to failing health checks to the regional load balancer ingress.
  - alert: Probe_Ingress_Region_Unhealthy
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 10m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: a domain probe from ${var.dc} reached an haproxy outside the local region
      description: A cloudprober probe to the domain reached an haproxy outside of the local region. This means that cloudflare may not be routing requests to ${var.dc}, likely due to failing health checks to the regional load balancer ingress.
  - alert: Probe_Latency_High
    expr: (cloudprober_latency{probe="latency"} > 1500) or (cloudprober_latency{probe="latency_https"} > 1500)
    for: 2m
    labels:
      service: infra
      severity: warning
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has high latency
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} has had high latency for 2 minutes, most recently at {{ $value }} ms.
  - alert: Probe_Latency_High
    expr: (cloudprober_latency{probe="latency"} > 3000) or (cloudprober_latency{probe="latency_https"} > 3000)
    for: 5m
    labels:
      service: infra
      severity: critical
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has extremely high latency
      description: The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }} has extremely high latency for 5 minutes, most recently at {{ $value }} ms.

- name: system_alerts
  rules:
  - alert: System_CPU_Usage_High
    expr: 100 - cpu_usage_idle > 70
    for: 5m
    labels:
      host: "{{ $labels.host }}"
      service: infra
      severity: warning 
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} has had CPU usage > 70% for 5 minutes
      description: host {{ $labels.host }} in ${var.dc} has had a CPU running at over 70% in the last 5 minutes. It was most recently at {{ $value | printf "%.2f" }}%.
  - alert: System_Memory_Available_Low
    expr: (mem_total - mem_available) / mem_total * 100 > 80
    for: 5m
    labels:
      host: "{{ $labels.host }}"
      service: infra
      severity: warning
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} has had memory usage > 80% for 5 minutes.
      description: host {{ $labels.host }} in ${var.dc} is utilizing over 80% of its memory in the last 5 minutes. It was most recently at {{ $value | printf "%.2f"}}%.
  - alert: System_Disk_Used_High
    expr: disk_used_percent > 90
    for: 5m
    labels:
      host: "{{ $labels.host }}"
      service: infra
      severity: warning
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} is using over 90% of its disk space
      description: host {{ $labels.host }} in ${var.dc} is using over 90% of its disk space. It was most recently at {{ $value | printf "%.2f" }}%.
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