variable "dc" {
  type = string
}

job "log-shipping" {
  datacenters = [var.dc]
  type = "system"
  // namespace = "logs"
  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
  }
  group "log-shipping" {
    count = 1
    network {
      port "promtail-healthcheck" {
        to = 3000
      }
    }
    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }
    ephemeral_disk {
      size = 300
    }
    task "nomad-forwarder" {
      driver = "docker"
      env {
        VERBOSE    = 4
        LOG_TAG    = "logging"
        LOG_FILE   = "${NOMAD_ALLOC_DIR}/nomad-logs.log"
        # this is the IP of the docker0 interface
        # and Nomad has been explicitly told to listen on it so that Docker tasks can communicate with the API
        NOMAD_ADDR = "http://${attr.unique.network.ip-address}:4646"
        # Nomad ACL token, could be sourced via template from Vault
#        NOMAD_TOKEN = "xxxx"
      }
      config {
        image = "sofixa/nomad_follower:latest"
      }
      # resource limits are a good idea because you don't want your log collection to consume all resources available
      resources {
        cpu    = 100
        memory = 512
      }
    }
    task "promtail" {
      driver = "docker"
      config {
        image = "grafana/promtail:2.7.4"
        args = [
          "-config.file",
          "local/config.yaml",
          "-print-config-stderr",
        ]
        ports = ["promtail-healthcheck"]
      }
      template {
        data = <<EOH
server:
  http_listen_port: 3000
  grpc_listen_port: 0

positions:
  filename: {{ env "NOMAD_ALLOC_DIR" }}/positions.yaml

client:
  url: http://{{ range service "loki" }}{{ .Address }}:{{ .Port }}{{ end }}/loki/api/v1/push
scrape_configs:
- job_name: local
  static_configs:
  - targets:
      - localhost
    labels:
      job: nomad
      __path__: "{{ env "NOMAD_ALLOC_DIR" }}/nomad-logs.log"
  pipeline_stages:
    # extract the fields from the JSON logs
    - json:
        expressions:
          alloc_id: alloc_id
          job_name: job_name
          job_meta: job_meta
          node_name: node_name
          service_name: service_name
          service_tags: service_tags
          task_meta: task_meta
          task_name: task_name
          message: message
          data: data
    # the following fields are used as labels and are indexed:
    - labels:
        job_name:
        task_name:
        service_name:
        node_name:
        service_tags:
    # use a regex to extract a field called time from within message( which is for non-JSON formatted logs,
    # so the assumption is that they're in the logfmt format,
    # and a field time= is present with a timestamp in, which is the actual timestamp of the log)
    - regex:
        expression: ".*time=\\\"(?P<timestamp>\\S*)\\\"[ ]"
        source: "message"
    - timestamp:
        source: timestamp
        format: RFC3339
EOH
        destination = "local/config.yaml"
      }
      # resource limits are a good idea because you don't want your log collection to consume all resources available
      resources {
        cpu    = 500
        memory = 512
      }
      service {
        name = "promtail"
        port = "promtail-healthcheck"
        check {
          type     = "http"
          path     = "/ready"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}