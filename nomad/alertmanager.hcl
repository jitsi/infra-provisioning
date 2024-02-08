variable "dc" {
  type = string
}

variable "alertmanager_hostname" {
  type = string
}

variable "alertmanager_version" {
  type = string
  default = "v0.26.0"
}

variable "slack_api_url" {
    type = string
    default = "replaceme"
}

variable "environment_type" {
  type = string
  default = "dev"
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"

  update {
    max_parallel = 1
    stagger      = "10s"
  }

  group "alertmanager" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "consul"
    }

    restart {
      attempts = 2
      interval = "30m"
      delay   = "15s"
      mode = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    network {
      port "alertmanager_ui" {
        to = 9093
      }
    }

    task "alertmanager" {
      user = "root"
      driver = "docker"

      config {
        image = "prom/alertmanager:${var.alertmanager_version}"
        force_pull = false
        ports = ["alertmanager_ui"]
        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml"
        ]
      }

      template {
        change_mode = "noop"
        destination = "local/alertmanager.yml"
        left_delimiter = "{{{"
        right_delimiter = "}}}"
        data = <<EOH
---
global:
  resolve_timeout: 5m
  slack_api_url: '${var.slack_api_url}'

route:
  group_by:
    - severity
    - type
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: slack

receivers:
  - name: slack
    slack_configs:
      - channel: '#nomad-${var.environment_type}'
        send_resolved: true
        title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in {{ .CommonLabels.environment }}) <{{- .GroupLabels.SortedPairs.Values | join " " }}>'
        text: |-
          <!channel>{{ range .Alerts }}
           
          *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
            {{- if .Annotations.description }}
          _{{ .Annotations.description }}_
            {{- end }}
          {{- end }}
#        actions:
#        - type: button
#          text: 'Runbook :green_book:'
#          url: '{{ (index .Alerts 0).Annotations.runbook }}'
#        - type: button
#          text: 'Dashboard :chart:'
#          url: '{{ (index .Alerts 0).Annotations.dashboard }}'
EOH
      }

      resources {
        cpu    = 500
        memory = 500
      }
        
      service {
        name = "alertmanager"
        tags = ["int-urlprefix-${var.alertmanager_hostname}/"]
        port = "alertmanager_ui"

        check {
          name     = "alertmanager_ui port alive"
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}