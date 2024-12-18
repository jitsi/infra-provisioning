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

variable "global_alertmanager" {
  type = bool
  default = false
}

variable "email_alert_url" {
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
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: silence

  routes:
    - matchers:
      - severity =~ "severe|warn|smoke"
      receiver: 'email_alerts'
      %{ if var.global_alertmanager }-global = "true"%{ endif -}
      continue: true
    - matchers:
      - severity =~ "severe|warn"
      receiver: 'slack_alerts'
      %{ if var.global_alertmanager }-global = "true"%{ endif -}
      continue: true
    %{ if var.pagerduty_enabled }- matchers:
      - severity = "severe"
      - global %{ if var.global_alertmanager }= "true"%{ else }!= "true"%{ endif }
      receiver: 'slack_pages'
      continue: true
    - matchers:
      - severity = "severe"
      - page = "true"
      - global %{ if var.global_alertmanager }= "true"%{ else }!= "true"%{ endif }
      receiver: 'pagerduty_alerts'
      continue: true%{ endif }

# suppress warn/smoke alerts if a severe alert is already firing with the same alertname
inhibit_rules:
  - source_matchers: [severity="severe"]
    target_matchers: [severity=~"warn|smoke"]
    equal: ['alertname']

receivers:
- name: silence
- name: email_alerts
  webhook_configs:
    - send_resolved: true
      url: '${var.email_alert_url}'
- name: slack_alerts
  slack_configs:
    - channel: '#jitsi-${var.slack_channel_suffix}'
      api_url: '{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_general_webhook }}}{{{ end }}}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in ${var.dc})'
      text: |-
        {{ if eq .CommonLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here>{{ end }}{{ end }}{{ range .Alerts }}
        *[{{ index .Labels "severity" | toUpper }}] {{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
        {{- if eq .Status "firing" }}{{- if .Annotations.description }}
        _{{ .Annotations.description }}_
        {{ end }}{{ if ne .Annotations.dashboard_url "" }}alert dashboard: {{ .Annotations.dashboard_url }}{{ end }}
        {{- if .Annotations.alert_url }}
        this alert: {{ .Annotations.alert_url }}{{ end }}
        {{- end }}
        {{- end }}
%{ if var.pagerduty_enabled }- name: 'pagerduty_alerts'
  pagerduty_configs:
  - service_key: '{{{ with secret "secret/default/alertmanager/receivers/pagerduty" }}}{{{ .Data.data.integration_key }}}{{{ end }}}'
- name: slack_pages
  slack_configs:
    - channel: '#pages'
      api_url: '{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_pages_webhook }}}{{{ end }}}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in ${var.dc})'
      text: |-
        {{ if eq .CommonLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here> - PAGE{{ if .CommonLabels.page }}{{ if ne .CommonLabels.page "true" }}-CANDIDATE{{ end }}{{ else }}-CANDIDATE{{ end }}{{ end }}{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}{{ if eq .Status "firing" }} - {{ if .Annotations.alert_url }}{{ .Annotations.alert_url }}{{ end }}{{ end }}
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