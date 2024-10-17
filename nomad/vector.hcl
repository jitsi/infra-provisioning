variable "dc" {
  type = string
}

variable "top_level_domain" {
  type = string
  default = "jitsi.net"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type = "system"
  priority = 75

  update {
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    progress_deadline = "10m"
    auto_revert = true
  }

  group "vector" {
    count = 1
    restart {
      attempts = 3
      interval = "10m"
      delay = "30s"
      mode = "delay"
    }
    network {
      port "api" {
        to = 8686
      }
      port "syslog" {
        static = 9000
      }
    }
    # docker socket volume
    volume "docker-sock-ro" {
      type = "host"
      source = "docker-sock-ro"
      read_only = true
    }
    ephemeral_disk {
      size    = 500
      sticky  = true
    }
    task "vector" {
      driver = "docker"
      config {
        image = "timberio/vector:0.28.1-alpine"
        ports = ["api","syslog"]
        volumes = [
          "/var/log/syslog:/var/log/syslog:ro",
        ]
      }
      # docker socket volume mount
      volume_mount {
        volume = "docker-sock-ro"
        destination = "/var/run/docker.sock"
        read_only = true
      }
      # Vector won't start unless the sinks(backends) configured are healthy
      env {
        VECTOR_CONFIG = "local/vector.toml"
        VECTOR_REQUIRE_HEALTHY = "true"
      }
      # resource limits are a good idea because you don't want your log collection to consume all resources available
      resources {
        cpu    = 64
        memory = 256
      }
      # template with Vector's configuration
      template {
        destination = "local/vector.toml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        # overriding the delimiters to [[ ]] to avoid conflicts with Vector's native templating, which also uses {{ }}
        left_delimiter = "[["
        right_delimiter = "]]"
        data=<<EOH
          data_dir = "alloc/data/vector/"
          [api]
            enabled = true
            address = "0.0.0.0:8686"
            playground = true
          [sources.jvb_logs]
            type = "docker_logs"
            include_containers = ["jvb-"]
            multiline.timeout_ms = 300
            multiline.mode = "halt_before"
            multiline.condition_pattern = "^(JVB|Exception) "
            multiline.start_pattern = "^(JVB|Exception) "
          [sources.jibri_logs]
            type = "docker_logs"
            include_containers = ["jibri-"]
            multiline.timeout_ms = 300
            multiline.mode = "halt_before"
            multiline.condition_pattern = "^(Jibri|Exception) "
            multiline.start_pattern = "^(Jibri|Exception) "
          [sources.jicofo_logs]
            type = "docker_logs"
            include_containers = ["jicofo-"]
            multiline.timeout_ms = 300
            multiline.mode = "halt_before"
            multiline.condition_pattern = "^(Jicofo|Exception) "
            multiline.start_pattern = "^(Jicofo|Exception) "
          [sources.loki_logs]
            type = "docker_logs"
            include_containers = ["loki-"]
            multiline.timeout_ms = 300
            multiline.mode = "halt_before"
            multiline.condition_pattern = "^level= "
            multiline.start_pattern = "^level= "
          [sources.logs]
            type = "docker_logs"
            exclude_containers = ["jicofo-","jvb-","jibri-","loki-"]
          [sources.syslog]
            type = "syslog"
            address = "0.0.0.0:9000"
            mode = "tcp"
          [sinks.loki_lokilogs]
            remove_timestamp = false
            type = "loki"
            inputs = ["loki_to_structure"]
            endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}"
            encoding.codec = "json"
            healthcheck.enabled = true
            # since . is used by Vector to denote a parent-child relationship, and Nomad's Docker labels contain ".",
            # we need to escape them twice, once for TOML, once for Vector
            # remove fields that have been converted to labels to avoid having the field twice
            remove_label_fields = true
                [sinks.loki_lokilogs.labels]
                    alloc = "{{ label.\"com.hashicorp.nomad.alloc_id\" }}"
                    job = "{{ label.\"com.hashicorp.nomad.job_name\" }}"
                    task = "{{ label.\"com.hashicorp.nomad.task_name\" }}"
                    group = "{{ label.\"com.hashicorp.nomad.task_group_name\" }}"
                    namespace = "logs"
                    node = "{{ label.\"com.hashicorp.nomad.node_name\" }}"
                    region = "[[ env "meta.cloud_region" ]]"
          [sinks.loki_syslog]
            remove_timestamp = false
            type = "loki"
            inputs = ["syslog"]
            endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}"
            encoding.codec = "json"
            healthcheck.enabled = true
            # since . is used by Vector to denote a parent-child relationship, and Nomad's Docker labels contain ".",
            # we need to escape them twice, once for TOML, once for Vector
            # remove fields that have been converted to labels to avoid having the field twice
            # remove_label_fields = true
                [sinks.loki_syslog.labels]
                    alloc = "[[ env "meta.cloud_instance_id" ]]"
                    job = "syslog"
                    task = "{{ .appname }}"
                    group = "syslog"
                    namespace = "system"
                    node = "[[ env "node.unique.name" ]]"
                    region = "[[ env "meta.cloud_region" ]]"
          [transforms.loki_to_structure]
            type = "remap"
            inputs = ["loki_logs"]
            source = """

            structured =
              parse_key_value(.message) ??
              parse_json(.message) ??
              {}
            . = merge(., structured) ?? .
            .timestamp = parse_timestamp(.ts, "%+") ?? .timestamp"""
          [transforms.message_to_structure]
            type = "remap"
            inputs = ["logs","jibri_logs","jicofo_logs","jvb_logs"]
            source = """
            structured =
              parse_json(.message) ??
              parse_regex(.message, r'^(?P<app>Jicofo) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<level>\\w+): \\[(?P<pid>\\d+)\\] (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<app>Jicofo) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<app>JVB) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<level>\\w+): \\[(?P<pid>\\d+)\\] (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<app>JVB) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<app>Jibri) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<level>\\w+): \\[(?P<pid>\\d+)\\] (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<app>Jibri) (?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}) (?P<level>\\w+): \\[(?P<pid>\\d+)\\] (?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<datetime>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}) (?P<component>\\w+)(\\s+)(?P<level>\\w+)\\t(?P<message>[\\S\\s]*)$') ??
              parse_regex(.message, r'^(?P<component>\\w+)(\\s+)(?P<level>\\w+)\\t(?P<message>[\\S\\s]*)$') ??
              parse_syslog(.message) ??
              parse_common_log(.message) ??
              parse_regex(.message, r'^(?P<timestamp>\\d+/\\d+/\\d+ \\d+:\\d+:\\d+) \\[(?P<severity>\\w+)\\] (?P<pid>\\d+)#(?P<tid>\\d+):(?: \\*(?P<connid>\\d+))? (?P<message>.*)$') ??
              {}
            . = merge(., structured) ?? ."""
          [sinks.out]
            type = "console"
            inputs = [ "message_to_structure" ]
            encoding.codec = "json"
          [sinks.loki]
            remove_timestamp = false
            type = "loki"
            inputs = ["message_to_structure"]
            endpoint = "https://[[ env "meta.environment" ]]-[[ env "meta.cloud_region" ]]-loki.${var.top_level_domain}"
            encoding.codec = "json"
            healthcheck.enabled = true
            # since . is used by Vector to denote a parent-child relationship, and Nomad's Docker labels contain ".",
            # we need to escape them twice, once for TOML, once for Vector
            # remove fields that have been converted to labels to avoid having the field twice
            remove_label_fields = true
                [sinks.loki.labels]
                    alloc = "{{ label.\"com.hashicorp.nomad.alloc_id\" }}"
                    job = "{{ label.\"com.hashicorp.nomad.job_name\" }}"
                    task = "{{ label.\"com.hashicorp.nomad.task_name\" }}"
                    group = "{{ label.\"com.hashicorp.nomad.task_group_name\" }}"
                    namespace = "{{ label.\"com.hashicorp.nomad.namespace\" }}"
                    node = "{{ label.\"com.hashicorp.nomad.node_name\" }}"
                    region = "[[ env "meta.cloud_region" ]]"
        EOH
      }
      service {
        name = "vector"
        port = "api"
        tags = ["ip-${attr.unique.network.ip-address}"]
        check {
          port     = "api"
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "5s"
        }
      }
      kill_timeout = "30s"
    }
  }
}