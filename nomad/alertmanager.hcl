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

variable "slack_api_url" {
    type = string
    default = "replaceme"
}

variable "pagerduty_keys_by_service" {
    type = string
    default = "{ \"default\": \"replaceme\" }"
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
{{{ $pagerduty_keys_by_service := (`${var.pagerduty_keys_by_service}` | parseJSON ) }}}
route:
  receiver: notification_hook
  group_by:
    - alertname
    - environment
    - service
    - severity
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h

  routes:
  - receiver: 'notification_hook'
    matcher:
      - severity =~ "low|warning|critical"
  - receiver: 'slack_infra'
    matcher:
      - service = 'infra'
      - severity =~ "warning|critical"
  - receiver: 'slack_jitsi'
    matcher:
      - service = 'jitsi'
      - severity =~ "warning|critical"
  {{{ range $k, $v := $pagerduty_keys_by_service -}}}
  - receiver: 'pagerduty-{{{ $k }}}'
    match:
      service: '{{{ $k }}}'
      severity: critical
  {{{- end }}}

receivers:
- name: notification_hook
  webhook_configs:
    - send_resolved: true
      url: '${var.notification_webhook_url}'
- name: slack_jitsi
  slack_configs:
    - channel: '#jitsi-${var.slack_channel_suffix}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in {{ .CommonLabels.environment }}) <{{- .GroupLabels.SortedPairs.Values | join " " }}>'
      text: |-
        {{ if eq .GroupLabels.severity "critical" }}<!here>{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
          {{- if .Annotations.description }}
        _{{ .Annotations.description }}_
          {{- end }}
        {{- end }}
- name: slack_infra
  slack_configs:
    - channel: '#infra-${var.slack_channel_suffix}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }} in {{ .CommonLabels.environment }}) <{{- .GroupLabels.SortedPairs.Values | join " " }}>'
      text: |-
        {{ if eq .GroupLabels.severity "critical" }}<!here>{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
          {{- if .Annotations.description }}
        _{{ .Annotations.description }}_
          {{- end }}
        {{- end }}
{{{ range $k, $v := $pagerduty_keys_by_service -}}}
- name: 'pagerduty-{{{ $k }}}'
  pagerduty_configs:
  - service_key: '{{{ $v }}}'
{{{ end }}}

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