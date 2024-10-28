variable "dc" {
  type = string
}

variable "alertmanager_hostname" {
  type = string
}

variable "alertmanager_version" {
  type = string
  default = "v0.27.0"
}

variable "notification_webhook_url" {
  type = string
}

variable "slack_channel_suffix" {
  type = string
  default = "dev"
}

variable "pagerduty_enabled" {
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

      vault {
        change_mode = "noop"
      }

      config {
        image = "prom/alertmanager:${var.alertmanager_version}"
        force_pull = false
        ports = ["alertmanager_ui"]
        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml"
        ]
      }

      template {
        destination = "local/alertmanager.yml"
        left_delimiter = "{{{"
        right_delimiter = "}}}"
        data = <<EOH
---
global:
  resolve_timeout: 5m
  slack_api_url: "{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_general_webhook }}}{{{ end }}}"

route:
  group_by: ['alertname', 'service', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: slack_alerts

  routes:
    - matchers:
      - service = "skip"
      - severity =~ "severe|warn|smoke"
      receiver: 'notification_hook'
      continue: true
    - matchers:
      - severity =~ "severe|warn"
      receiver: 'slack_alerts'
      continue: true
    %{ if var.pagerduty_enabled }- matchers:
      - severity = "severe"
      receiver: 'slack_pages'
      continue: true
    - matchers:
      - severity = "severe"
      - page = "true"
      receiver: 'pagerduty_alerts'
      continue: true%{ endif }

# suppress warn/smoke alerts if a severe alert is already firing with the same alertname
inhibit_rules:
  - source_matchers:
    - severity = "severe"
    target_matchers:
      - severity =~ "warn|smoke"
    equal: ['alertname', 'service']

receivers:
- name: notification_hook
  webhook_configs:
    - send_resolved: true
      url: '${var.notification_webhook_url}'
- name: slack_alerts
  slack_configs:
    - channel: '#jitsi-${var.slack_channel_suffix}'
      api_url: '{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_general_webhook }}}{{{ end }}}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in {{ .CommonLabels.environment }}) <{{- .GroupLabels.SortedPairs.Values | join " " }}>'
      text: |-
        {{ if eq .GroupLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here>{{ end }}{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
        {{- if eq .Status "firing" }}{{- if .Annotations.description }}
        _{{ .Annotations.description }}_
        {{ end }}view this alert in prometheus: {{ if .Annotations.url }}{{ .Annotations.url }}{{ end }}
        {{- end }}
        {{- end }}
%{ if var.pagerduty_enabled }- name: 'pagerduty_alerts'
  pagerduty_configs:
  - service_key: '{{{ with secret "secret/default/alertmanager/receivers/pagerduty" }}}{{{ .Data.data.integration_key }}}{{{ end }}}'
- name: slack_pages
  slack_configs:
    - channel: '#pages'
      api_url: '{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_pages_webhook }}}{{{ end }}}'
      send_resolved: false
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in {{ .CommonLabels.environment }}) <{{- .GroupLabels.SortedPairs.Values | join " " }}>'
      text: |-
        {{ if eq .GroupLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here>{{ end }}{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}{{ if eq .Status "firing" }} - {{ if .Annotations.url }}{{ .Annotations.url }}{{ end }}{{ end }}
        {{- end }}
%{ endif }
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