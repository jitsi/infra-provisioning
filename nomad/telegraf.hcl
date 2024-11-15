variable "environment" {
    type = string
}

variable "dc" {
  type = string
}

variable cloud_provider {
    type = string
    default = "oracle"
}

variable wavefront_proxy_url {
    type = string
    default = "http://localhost:2878"
}

variable wavefront_enabled {
  type = bool
  default = false
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "system"
  priority    = 75

  meta {
    environment = "${var.environment}"
    cloud_provider = "${var.cloud_provider}"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "telegraf" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "10m"
      mode = "delay"
    }

    network {
      mode = "host"
      port "telegraf-statsd" {
        static = 8125
      }
      port "telegraf-prometheus" {
      }
    }
    # docker socket volume
    volume "root-ro" {
      type = "host"
      source = "root-ro"
      read_only = true
    }

    task "telegraf" {
      service {
        name = "telegraf"
        tags = ["ip-${attr.unique.network.ip-address}"]
        port = "telegraf-prometheus"
        check {
          name     = "alive"
          type     = "http"
          path     = "/"
          port     = "telegraf-prometheus"
          interval = "10s"
          timeout  = "2s"
        }
      }

      user = "telegraf:999"
      driver = "docker"
      meta {
      }
      volume_mount {
        volume = "root-ro"
        destination = "/hostfs"
        read_only = true
        propagation_mode = "host-to-task"
      }
      config {
        network_mode = "host"
        privileged = true
        image        = "telegraf:1.29.5"
        ports = ["telegraf-statsd","telegraf-prometheus"]
        volumes = ["local/telegraf.conf:/etc/telegraf/telegraf.conf", "local/consul-resolved.conf:/etc/systemd/resolved.conf.d/consul.conf", "/var/run/docker.sock:/var/run/docker.sock"]
      }
      env {
	    HOST_ETC = "/hostfs/etc"
	    HOST_PROC = "/hostfs/proc"
	    HOST_SYS = "/hostfs/sys"
	    HOST_VAR = "/hostfs/var"
	    HOST_RUN = "/hostfs/run"
	    HOST_MOUNT_PREFIX = "/hostfs"
      }

      template {
        destination = "local/consul-resolved.conf"
        data = <<EOF
[Resolve]
DNS={{ env "attr.unique.network.ip-address" }}:8600
DNSSEC=false
Domains=~consul
EOF
      }

      template {
        data = <<EOF
[agent]
  interval = "20s"
  round_interval = false
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "60s"
  flush_jitter = "0s"
  precision = ""
  debug = true
  quiet = false
  hostname = "{{ env "attr.unique.hostname" }}"
  omit_hostname = false

[[inputs.nomad]]
  url = "http://{{ env "NOMAD_IP_telegraf_statsd" }}:4646"

[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  perdevice = false
  total_include = ["cpu", "network"]
  tagexclude = ["org.opencontainers.image.revision","engine_host","org.opencontainers.image.version","container_status","container_name","container_id","com.hashicorp.nomad.alloc_id","org.opencontainers.image.title","container_verison", "com.hashicorp.nomad.namespace","server_version","container_image"]
  namepass = ["docker_container_cpu*","docker_container_mem*","docker_container_net*"]

[[inputs.cpu]]
  percpu = false
  totalcpu = true
  collect_cpu_time = false
  report_active = false
  fielddrop = ["time_*"]
  fieldinclude = ["usage_system*", "usage_user*", "usage_iowait*", "usage_idle*", "usage_steal*"]

[[inputs.mem]]
  fieldinclude = [ "active", "available", "buffered", "cached", "free", "total",  "used" ]

[[inputs.net]]
  fieldinclude = ["bytes*","drop*","packets*","err*","tcp_retranssegs","udp_rcvbuferrors"]
  ignore_protocol_stats = false

[[inputs.processes]]
  fieldinclude = ["blocked", "idle", "paging", "running", "total*"]

[[inputs.swap]]
  fieldinclude = ["total", "used"]

[[inputs.system]]
  fieldinclude = ["load*"]

[[inputs.linux_sysctl_fs]]

[[inputs.statsd]]
  service_address = ":{{ env "NOMAD_HOST_PORT_telegraf_statsd" }}"
  delete_gauges = true
  delete_counters = true
  delete_sets = true
  delete_timings = true
  percentiles = [90]
  metric_separator = "_"
  allowed_pending_messages = 10000
  percentile_limit = 1000
  datadog_extensions = true

{{ range $index, $service := service "canary" }}
{{ if eq .Address (env "attr.unique.network.ip-address") }}
[[inputs.nginx]]
  urls = ["http://{{ .Address }}:{{ .Port }}/nginx_status"]
  [inputs.nginx.tags]
    host = "{{.Node}}"
    service = "canary"
{{ end }}
{{ end }}

[[inputs.prometheus]]
  http_headers = {"Accept" = "text/plain; version=0.0.4"}
  [inputs.prometheus.consul]
    enabled = true
    agent = "{{ env "attr.unique.network.ip-address" }}:8500"
    query_interval = "1m"
    [[inputs.prometheus.consul.query]]
      name = "jicofo"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "core"
        service = "jicofo"
        datacenter = "{{ env "NOMAD_META_datacenter" }}"
    [[inputs.prometheus.consul.query]]
      name = "prosody-http"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "core"
        prosody-type = "prosody"
        service = "prosody"
    [[inputs.prometheus.consul.query]]
      name = "prosody-jvb-http"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "core"
        prosody-type = "prosody-jvb"
        service = "prosody-jvb"
    [[inputs.prometheus.consul.query]]
      name = "shard-web"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "core"
        service = "nginx-shard"
    [[inputs.prometheus.consul.query]]
      name = "signal-sidecar"
      tag = "ip-{{ env "NOMAD_IP_telegraf_statsd" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "core"
        service = "signal-sidecar"
    [[inputs.prometheus.consul.query]]
      name = "coturn"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:9641/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "coturn"
        service = "coturn"
    [[inputs.prometheus.consul.query]]
      name = "autoscaler"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "autoscaler"
        service = "autoscaler"
    [[inputs.prometheus.consul.query]]
      name = "skynet"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "skynet"
        service = "skynet"
    [[inputs.prometheus.consul.query]]
      name = "recovery-agent"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}/metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "recovery-agent"
        service = "recovery-agent"
    [[inputs.prometheus.consul.query]]
      name = "whisper"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "whisper"
        service = "whisper"
    [[inputs.prometheus.consul.query]]
      name = "redis-metrics"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "redis"
        service = "redis"
        redis-index = "{{"{{"}}with .ServiceMeta.redis_index}}{{"{{"}}.}}{{"{{"}}else}}NA{{"{{"}}end}}"
    [[inputs.prometheus.consul.query]]
      name = "jibri"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        group = "{{"{{"}}with .ServiceMeta.group}}{{"{{"}}.}}{{"{{"}}else}}jibri{{"{{"}}end}}"
        jibri_version = "{{"{{"}}with .ServiceMeta.jibri_version}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        jibri_release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "java-jibri"
        service = "jibri"
    [[inputs.prometheus.consul.query]]
      name = "vo-credentials-store"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "credentials-store"
        service = "credentials-store"
    [[inputs.prometheus.consul.query]]
      name = "docker-registry"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}/metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "docker-registry"
        service = "docker-registry"
    [[inputs.prometheus.consul.query]]
      name = "docker-dhmirror"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}/metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "docker-dhmirror"
        service = "docker-dhmirror"
    [[inputs.prometheus.consul.query]]
      name = "transcriber"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        group = "{{"{{"}}with .ServiceMeta.group}}{{"{{"}}.}}{{"{{"}}else}}transcriber{{"{{"}}end}}"
        jigasi_version = "{{"{{"}}with .ServiceMeta.jigasi_version}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        jigasi_release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "transcriber"
        service = "transcriber"

[[inputs.prometheus]]
  namepass = [
    "jitsi_jvb_active_endpoints",
    "jitsi_jvb_average_rtt",
    "jitsi_jvb_colibri_web_socket_*",
    "jitsi_jvb_conference_seconds_total",
    "jitsi_jvb_conferences",
    "jitsi_jvb_conferences_by_size*",
    "jitsi_jvb_conferences_inactive",
    "jitsi_jvb_conferences_p2p",
    "jitsi_jvb_conferences_with_relay",
    "jitsi_jvb_current_endpoints",
    "jitsi_jvb_current_visitors",
    "jitsi_jvb_data_channel_messages_received_total",
    "jitsi_jvb_data_channel_messages_sent_total",
    "jitsi_jvb_dominant_speaker_changes_total",
    "jitsi_jvb_endpoints_disconnected_total",
    "jitsi_jvb_endpoints_dtls_failed_total",
    "jitsi_jvb_endpoints_inactive",
    "jitsi_jvb_endpoints_no_message_transport_after_delay_total",
    "jitsi_jvb_endpoints_oversending",
    "jitsi_jvb_endpoints_reconnected_total",
    "jitsi_jvb_endpoints_recvonly",
    "jitsi_jvb_endpoints_relayed",
    "jitsi_jvb_endpoints_sending_audio",
    "jitsi_jvb_endpoints_sending_video",
    "jitsi_jvb_endpoints_with_high_outgoing_loss",
    "jitsi_jvb_endpoints_with_spurious_remb",
    "jitsi_jvb_endpoints_with_suspended_sources",
    "jitsi_jvb_graceful_shutdown",
    "jitsi_jvb_healthy",
    "jitsi_jvb_ice_failed_total",
    "jitsi_jvb_ice_succeeded_*",
    "jitsi_jvb_incoming_bitrate",
    "jitsi_jvb_incoming_loss_fraction",
    "jitsi_jvb_incoming_packet_rate",
    "jitsi_jvb_jvm_*",
    "jitsi_jvb_keyframes_received_total",
    "jitsi_jvb_largest_conference",
    "jitsi_jvb_layering_changes_received_total",
    "jitsi_jvb_local_endpoints",
    "jitsi_jvb_loss_fraction",
    "jitsi_jvb_muc_clients_configured",
    "jitsi_jvb_muc_clients_connected",
    "jitsi_jvb_mucs_connected",
    "jitsi_jvb_mucs_joined",
    "jitsi_jvb_outgoing_bitrate",
    "jitsi_jvb_outgoing_loss_fraction",
    "jitsi_jvb_outgoing_packet_rate",
    "jitsi_jvb_participants",
    "jitsi_jvb_queue_*",
    "jitsi_jvb_relay_incoming_bitrate",
    "jitsi_jvb_relay_incoming_packet_rate",
    "jitsi_jvb_relay_outgoing_bitrate",
    "jitsi_jvb_relay_outgoing_packet_rate",
    "jitsi_jvb_relays_no_message_transport_after_delay_total",
    "jitsi_jvb_rtcp_transit_time",
    "jitsi_jvb_rtp_transit_time",
    "jitsi_jvb_startup_time",
    "jitsi_jvb_stress",
    "jitsi_jvb_thread_count",
    "jitsi_jvb_video_milliseconds_received_total"
  ]
  [inputs.prometheus.consul]
    enabled = true
    agent = "{{ env "attr.unique.network.ip-address" }}:8500"
    query_interval = "30s"
    [[inputs.prometheus.consul.query]]
      name = "jvb"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        jvb_release_number = "{{"{{"}}with .ServiceMeta.jvb_release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        role = "JVB"
        service = "jvb"
        region = "{{ env "meta.cloud_region" }}"
        oracle_region = "{{ env "meta.cloud_region" }}"
        jvb_version = "{{"{{"}}with .ServiceMeta.jvb_version}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"

[[inputs.prometheus]]
  name_prefix = "cloudprober_"
  [inputs.prometheus.consul]
    enabled = true
    agent = "{{ env "attr.unique.network.ip-address" }}:8500"
    query_interval = "30s"
    [[inputs.prometheus.consul.query]]
      name = "cloudprober"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "cloudprober"

[[inputs.prometheus]]
  namepass = ["DCGM_FI_DEV_GPU_UTIL*", "DCGM_FI_DEV_MEM_COPY_UTIL*"]
  [inputs.prometheus.consul]
    enabled = true
    agent = "{{ env "attr.unique.network.ip-address" }}:8500"
    query_interval = "1m"
    [[inputs.prometheus.consul.query]]
      name = "gpu-monitor"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        role = "gpu"
        service = "gpu"

[[ inputs.internal ]]
  name_prefix = "telegraf_"
  collect_memstats = false
  collect_gostats = false

[[outputs.prometheus_client]]
  listen = ":{{ env "NOMAD_HOST_PORT_telegraf_prometheus" }}"
  path = "/metrics"

%{ if var.wavefront_enabled }[[outputs.wavefront]]
  url = "${var.wavefront_proxy_url}"
  metric_separator = "."
  source_override = ["hostname", "snmp_host", "node_host"]
  convert_paths = true
  use_regex = false
%{ endif }
[global_tags]
  environment = "{{ env "NOMAD_META_environment" }}"
  region = "{{ env "meta.cloud_region" }}"
  cloud = "{{  env "NOMAD_META_cloud_provider" }}"
  cloud_provider = "{{ env "NOMAD_META_cloud_provider" }}"
  pool_type = "{{ env "meta.pool_type" }}"
{{ with env "meta.selenium_grid_name" }}  grid = "{{ . }}"{{ end }}

EOF
        destination = "local/telegraf.conf"
      }
      // resources {
      //   cpu    = 500
      //   memory = 768
      // }
    }
  }
}
