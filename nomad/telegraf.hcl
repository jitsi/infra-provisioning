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


job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "system"

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

    network {
      mode = "host"
      port "telegraf-statsd" {
        static = 8125
      }
    }
    # docker socket volume
    volume "root-ro" {
      type = "host"
      source = "root-ro"
      read_only = true
    }

    task "telegraf" {
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
        image        = "telegraf:latest"
        ports = ["telegraf-statsd"]
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
  interval = "60s"
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
  total = true
  tagexclude = ["org.opencontainers.image.revision","engine_host","org.opencontainers.image.version","container_status","container_name","container_id","com.hashicorp.nomad.alloc_id","org.opencontainers.image.title","container_verison", "com.hashicorp.nomad.namespace","server_version","container_image"]
  namepass = ["docker_container_cpu*","docker_container_mem*","docker_container_net"]

[[inputs.cpu]]
  percpu = false
  totalcpu = true
  collect_cpu_time = false
  report_active = false
  fielddrop = ["time_*"]
  fieldpass = ["usage_system*", "usage_user*", "usage_iowait*", "usage_idle*", "usage_steal*"]

[[inputs.mem]]
  fieldpass = [ "active", "available", "buffered", "cached", "free", "total",  "used" ]

[[inputs.net]]
  fieldpass = ["bytes*","drop*","packets*","err*","tcp*","udp*"]

[[inputs.processes]]
  fieldpass = ["blocked", "idle", "paging", "running", "total*"]

[[inputs.swap]]
  fieldpass = ["total", "used"]

[[inputs.system]]
  fieldpass = ["load*"]

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

{{ range $index, $service := service "signal"}}
{{if eq .ServiceMeta.nginx_status_ip (env "attr.unique.network.ip-address") }}
[[inputs.nginx]]
{{ with .ServiceMeta }}
  urls = ["http://{{ .nginx_status_ip }}:{{ .nginx_status_port }}/nginx_status"]
  [inputs.nginx.tags]
    shard = "{{ .shard }}"
    release_number = "{{ .release_number }}"
    shard-role = "core"
    role = "core"
{{ end }}
{{ end }}
{{ end }}

[[inputs.prometheus]]
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
        shard-role = "core"
        role = "core"
    [[inputs.prometheus.consul.query]]
      name = "prosody-http"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        shard-role = "core"
        role = "core"
        prosody-type = "prosody"
    [[inputs.prometheus.consul.query]]
      name = "prosody-jvb-http"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        shard-role = "core"
        role = "core"
        prosody-type = "prosody-jvb"
    [[inputs.prometheus.consul.query]]
      name = "signal-sidecar"
      tag = "ip-{{ env "NOMAD_IP_telegraf_statsd" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard = "{{"{{"}}with .ServiceMeta.shard}}{{"{{"}}.}}{{"{{"}}else}}shard{{"{{"}}end}}"
        release_number = "{{"{{"}}with .ServiceMeta.release_number}}{{"{{"}}.}}{{"{{"}}else}}0{{"{{"}}end}}"
        shard-role = "core"
        role = "core"
    [[inputs.prometheus.consul.query]]
      name = "coturn"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:9641/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard-role = "coturn"
        role = "coturn"
    [[inputs.prometheus.consul.query]]
      name = "autoscaler"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}.ServicePort}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard-role = "autoscaler"
        role = "autoscaler"
    [[inputs.prometheus.consul.query]]
      name = "skynet"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}summaries/metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard-role = "skynet"
        role = "skynet"

[[inputs.prometheus]]
  name_prefix = "jitsi_oscar_"
  [inputs.prometheus.consul]
    enabled = true
    agent = "{{ env "attr.unique.network.ip-address" }}:8500"
    query_interval = "1m"
    [[inputs.prometheus.consul.query]]
      name = "oscar"
      tag = "ip-{{ env "attr.unique.network.ip-address" }}"
      url = 'http://{{"{{"}}if ne .ServiceAddress ""}}{{"{{"}}.ServiceAddress}}{{"{{"}}else}}{{"{{"}}.Address}}{{"{{"}}end}}:{{"{{"}}with .ServiceMeta.metrics_port}}{{"{{"}}.}}{{"{{"}}else}}{{"{{"}}.ServicePort}}{{"{{"}}end}}/{{"{{"}}with .ServiceMeta.metrics_path}}{{"{{"}}.}}{{"{{"}}else}}metrics{{"{{"}}end}}'
      [inputs.prometheus.consul.query.tags]
        host = "{{"{{"}}.Node}}"
        shard-role = "oscar"
        role = "oscar"

[[outputs.wavefront]]
  url = "${var.wavefront_proxy_url}"
  metric_separator = "."
  source_override = ["hostname", "snmp_host", "node_host"]
  convert_paths = true
  use_regex = false

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
    }
  }
}