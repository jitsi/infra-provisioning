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

variable "production_alerts" {
  type = bool
  default = false
}

variable "core_deployment" {
  type = bool
  default = false
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
      severity: severe
    annotations:
      summary: alertmanager service is down in ${var.dc}
      description: >
        Metrics from alertmanager are not being received in ${var.dc}. This
        means that alerts are not being emitted from the datacenter. Thus, the
        fact that you received an alert from this datacenter is quite curious
        indeed.
      url: https://${var.prometheus_hostname}/alerts?search=alertmanager_down
  - alert: Cloudprober_Down
    expr: absent(up{job="cloudprober"})
    for: 5m
    labels:
      service: infra
      severity: warn
    annotations:
      summary: cloudprober service is down in ${var.dc}
      description: >
        Metrics from cloudprober are not being received in ${var.dc}. This means
        that data from synthetic probes is not being collected or alerted on in
        this datacenter.
      url: https://${var.prometheus_hostname}/alerts?search=cloudprober_down
  - alert: Consul_Down
    expr: count(consul_server_isLeader) < 3
    for: 5m
    labels:
      service: infra
      severity: warn
    annotations:
      summary: there are fewer than 3 consul servers in ${var.dc}
      description: >
        There are fewer than 3 consul servers in ${var.dc}, which means the
        cluster is not complete. This may mean that service discovery may not be
        functioning. Currently there are {{ $value }} servers.
      url: https://${var.prometheus_hostname}/alerts?search=consul_down
  - alert: Consul_Down
    expr: absent(consul_server_isLeader)
    for: 5m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: the consul cluster is down in ${var.dc}
      description: >
        The consul cluster in ${var.dc} is not emitting metrics and may be
        entirely down. This may mean that service discovery may not be
        functioning and all service may be compromised.
      url: https://${var.prometheus_hostname}/alerts?search=consul_down
  - alert: Nomad_Down
    expr: count(nomad_runtime_alloc_bytes) < 3
    for: 5m
    labels:
      service: infra
      severity: warn
    annotations:
      summary: nomad service is compromised in ${var.dc}
      description: >
        There are fewer than 3 nomad clients emitting metrics in ${var.dc}. This
        may mean that service orchestration and job placement are not functioning.
      url: https://${var.prometheus_hostname}/alerts?search=nomad_down
  - alert: Nomad_Down
    expr: absent(nomad_runtime_alloc_bytes)
    for: 5m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: nomad service is completely down in ${var.dc}
      description: >
        No nomad clients are emitting metrics in ${var.dc}. This may mean that
        service orchestration and job placement are not functioning.
      url: https://${var.prometheus_hostname}/alerts?search=nomad_down
  - alert: Prometheus_Down
    expr: absent(up{job="prometheus"})
    for: 5m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: prometheus service is down in ${var.dc}
      description: >
        No prometheus services are emitting metrics in ${var.dc}. This may mean
        that no metrics are being stored or served.
      url: https://${var.prometheus_hostname}/alerts?search=prometheus_down
  - alert: Telegraf_Down
    expr: nomad_nomad_heartbeat_active > (sum(up{job="telegraf"}) or vector(0))
    for: 5m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: telegraf services are down on some nodes in ${var.dc}
      description: >
        telegraf metrics are not being emitted from all nodes in ${var.dc}.
        Metrics for some services are not being collected.
      url: https://${var.prometheus_hostname}/alerts?search=telegraf_down
  - alert: Canary_Down
    expr: absent(nginx_accepts{service="canary"})
    for: 5m
    labels:
      page: true
      service: infra
      severity: severe
    annotations:
      summary: canary service is down in ${var.dc}
      description: The canary service is down in ${var.dc}. Latency metrics are not being collected.
      url: https://${var.prometheus_hostname}/alerts?search=canary_down

- name: cloudprober_alerts
  rules:
  - alert: Probe_Unhealthy_Warn
    expr: (cloudprober_failure{probe!="shard"} > 0) or (cloudprober_timeouts{probe!="shard"} > 0)
    for: 2m
    labels:
      severity: warn
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} unhealthy for 2+ minutes"
      description: >
        The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }}
        timed-out or received unhealthy responses for 2 minutes.
      url: https://${var.prometheus_hostname}/alerts?search=probe_unhealthy
  - alert: Probe_Unhealthy_Severe
    expr: (cloudprober_failure{probe!="shard"} > 0) or (cloudprober_timeouts{probe!="shard"} > 0)
    for: 5m
    labels:
      severity: "{{ if $labels.severity }}{{ $labels.severity }}{{ else }}severe{{ end }}"
    annotations:
      summary: "{{ $labels.probe }} probe from ${var.dc} to {{ $labels.dst }} unhealthy for 5+ minutes"
      description: >
        The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }}
        timed-out or received unhealthy responses for 5+ minutes.
      url: https://${var.prometheus_hostname}/alerts?search=probe_unhealthy
  - alert: Probe_Shard_Unhealthy
    expr: ((cloudprober_failure{probe="shard"} > 0) and on() count_over_time(cloudprober_failure{probe="shard"}[5m:1m]) > 5) or (cloudprober_timeouts{probe="shard"} > 0)
    for: 2m
    annotations:
      summary: shard {{ $labels.dst }} probe returned failed or timed-out from ${var.dc}
      description: >
        An internal probe from ${var.dc} to the {{ $labels.dst }} shard
        timed-out or received an unhealthy response from signal-sidecar. This
        may be due to a variety of issues. If a local probe failed it is likely
        due to an unhealthy prosody or jicofo, if it's a remote probe then there
        may be a network issue between regions.
      url: https://${var.prometheus_hostname}/alerts?search=probe_shard_unhealthy
  - alert: Probe_Ingress_Region_Unhealthy_Warn
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 2m
    labels:
      severity: warn 
    annotations:
      summary: domain probe from ${var.dc} reached an haproxy outside the local region for 2+ minutes
      description: >
        A cloudprober probe to the domain reached an haproxy outside of the
        local region. This means that cloudflare may not be routing requests to
        ${var.dc}, likely due to failing health checks to the regional load
        balancer ingress.
      url: https://${var.prometheus_hostname}/alerts?search=probe_ingress_region_unhealthy
  - alert: Probe_Ingress_Region_Unhealthy_Severe
    expr: cloudprober_haproxy_region_check_passed < 1
    for: 10m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: domain probes from ${var.dc} reached an haproxy outside the local region for 10+ minutes
      description: >
        Cloudprober probes from ${var.dc} to the domain reached an haproxy
        outside of the local region for over ten minutes. This means that
        cloudflare may not be routing requests to ${var.dc}, likely due to
        failing health checks to the regional load balancer ingress.
      url: https://${var.prometheus_hostname}/alerts?search=probe_ingress_region_unhealthy
  - alert: Probe_Latency_Warn
    expr: (cloudprober_latency{probe="latency"} > 1500) or (cloudprober_latency{probe="latency_https"} > 1500)
    for: 2m
    labels:
      severity: warn
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has had high latency 2+ minutes
      description: >
        The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }}
        has had latency over 1.5 seconds for 2 minutes, most recently at {{ $value }} ms.
      url: https://${var.prometheus_hostname}/alerts?search=probe_latency
  - alert: Probe_Latency_Severe
    expr: (cloudprober_latency{probe="latency"} > 3000) or (cloudprober_latency{probe="latency_https"} > 3000)
    for: 5m
    labels:
      service: infra
      severity: severe
    annotations:
      summary: http probe from ${var.dc} to {{ $labels.dst }} has extremely high latency for 5+ minutes
      description: >
        The {{ $labels.probe }} http probe from ${var.dc} to {{ $labels.dst }}
        has had latency over 3 seconds for 5 minutes, most recently at {{ $value }} ms.
      url: https://${var.prometheus_hostname}/alerts?search=probe_latency

- name: system_alerts
  rules:
  - alert: System_CPU_Usage_High
    expr: 100 - cpu_usage_idle > 90
    for: 5m
    labels:
      service: infra
      severity: warn
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} has had CPU usage > 90% for 5 minutes
      description: >
        host {{ $labels.host }} in ${var.dc} has had a CPU running at over 90%
        in the last 5 minutes. It was most recently at {{ $value | printf "%.2f" }}%.
      url: https://${var.prometheus_hostname}/alerts?search=system_cpu_usage_high
  - alert: System_Memory_Available_Low
    expr: (mem_total - mem_available) / mem_total * 100 > 80
    for: 5m
    labels:
      service: infra
      severity: warn
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} has had memory usage > 80% for 5 minutes.
      description: >
        host {{ $labels.host }} in ${var.dc} is utilizing over 80% of its memory
        in the last 5 minutes. It was most recently at {{ $value | printf "%.2f"}}%.
      url: https://${var.prometheus_hostname}/alerts?search=system_memory_available_low
  - alert: System_Disk_Used_High
    expr: disk_used_percent > 90
    for: 5m
    labels:
      service: infra
      severity: warn #### in WF: 85 warn, 90 severe
    annotations:
      summary: host {{ $labels.host }} in ${var.dc} is using over 90% of its disk space
      description: >
        host {{ $labels.host }} in ${var.dc} is using over 90% of its disk
        space. It was most recently at {{ $value | printf "%.2f" }}%.
      url: https://${var.prometheus_hostname}/alerts?search=system_disk_used_high
%{ if var.core_deployment }
- name: core_service_alerts
  rules:
  - alert: Jibris_Available_None [Available Jibris]
    expr: sum(jibri_available) == 0 or absent(jibri_available)
    for: 5m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: no jibris are available in ${var.dc}
      description: >
        No jibris are available in ${var.dc}. This means that no jibri instances
        are available to record or stream meetings.
      url: https://${var.prometheus_hostname}/alerts?search=jibris_available_none
  - alert: HAProxy_Shard_Unhealthy [HAProxy Unhealthy Agent Alarm]
    expr: min(haproxy_agent_health) < 1
    for: 1m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: unhealthy shard(s) in ${var.dc}
      description: >
        One or more shards is reporting unhealthy to at least one HAProxy in
        ${var.dc}. Check signal-sidecar logs on the shard to understand more.
        The HealthAnyAlarm email has also likely been triggered.
      url: https://${var.prometheus_hostname}/alerts?search=haproxy_unhealthy_agent
  - alert: Jicofo_JVB_Version_Mismatch
    expr: jitsi_jicofo_bridge_selector_bridge_version_count > 1
    for: 2h
    labels:
      service: jitsi
      severity: warn
      page: true
    annotations:
      summary: at least one jicofo in ${var.dc} has bridges with different version-release strings
      description: >
        A jicofo instance has bridges with different version-release strings in
        ${var.dc}. This may happen during a JVB pool upgrade; if this is not the
        case then cross-regional octo is likely broken, which will result in degraded service.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_jvb_version_mismatch
  - alert: Jicofo_Jibris_Missing [Jicofo Jibri]
    expr: max(jitsi_jicofo_jibri_instances) < 1
    for: 10m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: no jibris are available in ${var.dc}
      description: >
        No jibris are available in ${var.dc}. This means that no jibri instances
        are available to record or stream meetings.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_jibris_missing
  - alert: Jicofo_JVBs_Missing [Jicofo JVBs]
    expr: jitsi_jicofo_bridge_selector_bridge_count < 2    # 2 because remote + local
    for: 5m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: no jvbs are available in ${var.dc}
      description: >
        No jvbs are available in ${var.dc}. This means that no jvb instances
        are available to host meetings.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_jvbs_missing
  - alert: Jicofo_JVBs_Lost_High [Jicovo lost JVBs]
    expr: increase(jitsi_jicofo_bridge_selector_lost_bridges_total[1m]) > 4   # severe, >2 warn, >1 smoke
    for: 1m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: jicofo lost more than 4 jvbs in ${var.dc} within 1 minute.
      description: >
        Jicofo lost more than 4 jvbs in ${var.dc} within 1 minute, which may
        mean that some sort of failure is occurring.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_jvbs_lost_high
  - alert: Jicofo_SIP-Jigasi_Missing [Jicofo SIP Jigasi]
    expr: max(jitsi_jicofo_jigasi_sip_count) < 1    # < 2 warn
    for: 1m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: there are too few SIP jigasis in ${var.dc}
      description: >
        There are too few jicofo SIP jigasis in ${var.dc}. If this alarm is in
        SEVERE, they are missing; trigger a jigasi release. and override the git
        branch to match the running nodes. Consider expanding the release if the
        alarm is not SEVERE.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_sip-jigasi_missing
  - alert: Jicofo_Transcribers_Missing [Jicofo Transcribers]
    expr: max(jitsi_jicofo_jigasi_transcriber_count) < 1    # warn < 2
    for: 5m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: there are too few transcribers in ${var.dc}
      description: >
        Transcribers are missing. Consider running a transcriber release job, using the
        same git branch as those of the running nodes.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_transcribers_missing
  - alert: Jicofo_ICE_Restarts_High [Jicofo ICE Restart Notifications]
    expr: increase(jitsi_jicofo_participants_restart_requested_total[$__rate_interval]) > 300
    for: 2m
    labels:
      service: jitsi
      severity: warn
    annotations:
      summary: jicofo in ${var.dc} has had an unusually high number of ICE restarts
      description: >
        A jicofo in ${var.dc} has had too many ICE restarts and should be
        investigated.
      url: https://${var.prometheus_hostname}/alerts?search=jicofo_ice_restarts_high
  - alert: Coturn_UDP_Errors_High [Coturn UDP Errors]
    expr: sum(net_udp_rcvbuferrors{pool_type='coturn'}) by (environment) > 2000 # 5000 severe 2000 warn, 200 smoke
    for: 2m
    labels:
      service: jitsi
      severity: warn 
    annotations:
      summary: coturn UDP errors are high in ${var.dc}
      description: >
        Coturn UDP errors are high in ${var.dc}, likely due to them being
        overloaded or possibly due to network issues.
      url: https://${var.prometheus_hostname}/alerts?search=coturn_udp_errors_high
  - alert: JVB_CPU_High [JVB CPU]
    expr: 100 - cpu_usage_idle{role="JVB"} > 80  # 60 warn 50 smoke
    for: 5m
    labels:
      service: jitsi
      severity: warn
      page: true
    annotations:
      summary: a JVB in ${var.dc} has had CPU usage > 80% for 5 minutes
      description: >
        A JVB in ${var.dc} has had a CPU running at over 80% in the last 5
        minutes. It was most recently at {{ $value | printf "%.2f" }}%.
      url: https://${var.prometheus_hostname}/alerts?search=jvb_cpu_high
  - alert: JVB_ICE_Failures_High [JVB Ice Failed Endpoints]
    expr: jitsi_JVB_total_ice_failed > 1000
    for: 5m
    labels:
      service: jitsi
      severity: warn
    annotations:
      summary: a JVB in ${var.dc} has had too many ICE failures
      description: >
        A JVB in ${var.dc} has had too many ICE failures and should be
        investigated.
      url: https://${var.prometheus_hostname}/alerts?search=jvb_ice_failures_high
  - alert: JVB_RTP_Delay_High [JVB RTP Delay]
    expr: 100 * jitsi_JVB_transit_rtp_gt50ms / (jitsi_JVB_transit_rtp_total + 0.001) > 15
    for: 10m
    labels:
      service: jitsi
      severity: warn
    annotations:
      summary: a JVB in ${var.dc} has too much RTP delayed > 50ms
      description: >
        A JVB in ${var.dc} has had too many packets with a RTP delay > 50ms and
        should be investigated.
      url: https://${var.prometheus_hostname}/alerts?search=jvb_rtp_delay_high
  - alert: Whisper_Sessions_High [Meetings Whisper prod-8x8 sessions]
    expr: Skynet_Streaming_Whisper_LiveWsConnections > 6  # 10 sev, 8 warn, 6 smoke
    for: 1m
    labels:
      service: jitsi
      severity: smoke
    annotations:
      summary: too many concurrent whisper sessions in ${var.dc}
      description: >
        Whisper will give a bad experience if it has more than 10 sessions at
        once. When an instance is handling more than 6 sessions, it is time to
        scale up.
      url: https://${var.prometheus_hostname}/alerts?search=whisper_sessions_high
  - alert: HAProxy_Redispatch_Rate_High [HAProxy Redispatch Rate]
    expr: haproxy_wredis > 4     # 4 sev 3 warn 2 smoke
    for: 5m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: haproxy in ${var.dc} is redispatching too many requests
      description: >
        A HAProxy in ${var.dc} is unable to route requests to one or more
        shards, and has moved rooms to a different shard.  This is usually
        indicative of network issues between HAProxy and the shards, and may
        require draining one or more regions.
      url: https://${var.prometheus_hostname}/alerts?search=haproxy_redispatch_rate_high
  - alert: Jigasi_Dropped_Media [Jigasi Dropped Media]
    expr: increase(jitsi_jigasi_total_calls_with_dropped_media[1m]) > 1   # sev 5 warn 3 smoke 1
    for: 2m
    labels:
      service: jitsi
      severity: warn
    annotations:
      summary: a jigasi in ${var.dc} has dropped media
      description: >
        A jigasi in ${var.dc} dropped media for 10+ seconds during calls. A new
        jigasi release may be required to resolve the problem.
      url: https://${var.prometheus_hostname}/alerts?search=jigasi_dropped_media
  - alert: Shard_CPU_High [Shard CPU]
    expr: 100 - cpu_usage_idle{role="core"} > 90    # 80 warn 60 smoke
    for: 5m
    labels:
      service: jitsi
      severity: severe
      page: true
    annotations:
      summary: a shard in ${var.dc} has had CPU usage > 90% for 5 minutes
      description: >
        A shard in ${var.dc} has had a CPU running at over 90% in the last 5
        minutes. It was most recently at {{ $value | printf "%.2f" }}%.
        Utilization should ideally stay below 60%. Log in to the shard and
        determine what process is using the most CPU. If nothing seems out of
        the ordinary, the region may be overloaded. Launch new shards if the
        number of participants on each shard is over 4000 users.
      url: https://${var.prometheus_hostname}/alerts?search=shard_cpu_high
  - alert: Skynet_Queue_Depth_High [Skynet Queue Size]
    expr: Skynet_Summaries_summary_queue_size > 100   # 1000 sev 500 warn 100 smoke
    for: 5m
    labels:
      service: jitsi
      severity: smoke
    annotations:
      summary: skynet queue depth is high in ${var.dc}
      description: >
        Skynet has gotten behind in its queue in ${var.dc}. If all existing
        nodes are operating as expected, it may be neccessary to scale up the
        instance pool manually.
      url: https://${var.prometheus_hostname}/alerts?search=skynet_queue_depth_high
  - alert: Skynet_System_Load_High [Skynet System Load]
    expr: system_load1{pool_type="skynet"} > 5   # 10 sev 8 warn 5 smoke
    for: 5m
    labels:
      service: jitsi
      severity: smoke
    annotations:
      summary: skynet system load is high in ${var.dc}
      description: >
        Skynet has a higher than expected system load in ${var.dc}. Skynet may
        be stuck and deserve operator attention.
      url: https://${var.prometheus_hostname}/alerts?search=skynet_system_load_high
%{ endif }
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