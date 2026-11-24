# Per-service PagerDuty routing based on vault values:
#   - Default: secret/default/alertmanager/receivers/pagerduty (key
#     pagerduty_integration_key) -> receiver `pagerduty_alerts`.
#   - Overrides: each secret under .../receivers/pagerduty_services/<svc>
#     adds a `service = <svc>` route + `pagerduty_alerts_<svc>` receiver.

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

# A regional alertmanager sees only its own region's alerts, so a fleet-wide
# fault paged once per region. With this set, Prometheus also sends page=true
# alerts to the global alertmanager, which pages once; the regional one stops.
variable "pages_via_global" {
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
      dynamic "port" {
        for_each = var.global_alertmanager ? ["cluster"] : []
        labels   = [port.value]
        content {}
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
        ports = var.global_alertmanager ? ["alertmanager_ui", "cluster"] : ["alertmanager_ui"]
        entrypoint = var.global_alertmanager ? ["/bin/sh", "/local/start.sh"] : null
        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml"
        ]
      }

      # The global alertmanagers in each region of the environment form one
      # cluster, so only one of them sends each page. Peers are looked up in
      # every reachable datacenter once at start: a later re-render would tie
      # this task to the health of the other region's Consul.
      dynamic "template" {
        for_each = var.global_alertmanager ? ["local/start.sh"] : []
        content {
          destination = template.value
          once        = true
          data        = <<EOH
#!/bin/sh
exec /bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager \
  --cluster.listen-address=0.0.0.0:{{ env "NOMAD_PORT_cluster" }} \
  --cluster.advertise-address={{ env "NOMAD_IP_cluster" }}:{{ env "NOMAD_HOST_PORT_cluster" }}{{ range datacenters true }}{{ range service (printf "alertmanager-global-cluster@%s" .) }} \
  --cluster.peer={{ .Address }}:{{ .Port }}{{ end }}{{ end }}
EOH
        }
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
  group_by: ['alertname','environment']
  group_wait:     %{ if var.global_alertmanager }20s%{ else }10s%{ endif }  # wait time to create a new group
  group_interval:  1m  # wait time for a new alert that matches an existing group 
  repeat_interval: 4h  # wait time before re-sending a notification
  receiver: silence

  routes:
%{ if var.global_alertmanager && var.pagerduty_enabled }{{{ range secrets "secret/default/alertmanager/receivers/heartbeats" }}}    - matchers:
      - alertname = "Watchdog"
      receiver: 'heartbeat_{{{ . }}}'
      group_by: ['alertname']
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m
      continue: true
{{{ end }}}%{ endif }    - matchers:
      - severity =~ "severe|warn|smoke"
      - scope %{ if var.global_alertmanager }= "global"%{ else }!= "global"%{ endif }
      receiver: 'email_alerts'
      repeat_interval: 120h
      continue: true
    - matchers:
      - severity =~ "severe|warn"
      - scope %{ if var.global_alertmanager }= "global"%{ else }!= "global"%{ endif }
      receiver: 'slack_alerts'
      repeat_interval: 24h
      continue: true
    %{ if var.pagerduty_enabled }- matchers:
      - severity = "severe"
      %{ if !var.global_alertmanager }- scope != "global"
      %{ if var.pages_via_global }- page != "true"
      %{ endif }%{ endif }receiver: 'slack_pages'
      continue: true
%{ if var.global_alertmanager || !var.pages_via_global }{{{ range secrets "secret/default/alertmanager/receivers/pagerduty_services" }}}    - matchers:
      - severity = "severe"
      - page = "true"
      - service = "{{{ . }}}"
      %{ if !var.global_alertmanager }- scope != "global"
      %{ endif }receiver: 'pagerduty_alerts_{{{ . }}}'
      continue: false
{{{ end }}}    - matchers:
      - severity = "severe"
      - page = "true"
      %{ if !var.global_alertmanager }- scope != "global"
      %{ endif }receiver: 'pagerduty_alerts'%{ endif }%{ if !var.global_alertmanager && var.pages_via_global }    - matchers:
      - severity = "severe"
      - page_fallback = "true"
      receiver: 'pagerduty_alerts'%{ endif }%{ endif }

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
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }}) in %{ if var.global_alertmanager }{{ .CommonLabels.environment }} (GLOBAL)%{ else }${var.dc}%{ endif }'
      text: |-
        {{ if eq .CommonLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here>{{ end }}{{ end }}{{ range .Alerts }}
        *[{{ index .Labels "severity" | toUpper }}] {{ index .Labels "alertname" }}* in {{ index .Labels "datacenter" }} {{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}
        {{- if eq .Status "firing" }}{{- if .Annotations.description }}
        _{{ .Annotations.description }}_
        {{ end }}{{ if ne .Annotations.dashboard_url "" }}alert dashboard: {{ .Annotations.dashboard_url }}{{ end }}
        {{- if .Annotations.alert_url }}
        this alert: {{ .Annotations.alert_url }}{{ end }}
        start: {{ .StartsAt.UTC.Format "2006-01-02 15:04:05" }} UTC
        {{- else }}
        start: {{ .StartsAt.UTC.Format "2006-01-02 15:04:05" }} UTC
        resolved: {{ .EndsAt.UTC.Format "2006-01-02 15:04:05" }} UTC
        {{- end }}
        {{- end }}
%{ if var.pagerduty_enabled }- name: 'pagerduty_alerts'
  pagerduty_configs:
  - service_key: '{{{ with secret "secret/default/alertmanager/receivers/pagerduty" }}}{{{ .Data.data.pagerduty_integration_key }}}{{{ end }}}'
{{{ range secrets "secret/default/alertmanager/receivers/pagerduty_services" }}}{{{ $svc := . }}}- name: 'pagerduty_alerts_{{{ $svc }}}'
  pagerduty_configs:
  - service_key: '{{{ with secret (printf "secret/default/alertmanager/receivers/pagerduty_services/%s" $svc) }}}{{{ .Data.data.pagerduty_integration_key }}}{{{ end }}}'
{{{ end }}}%{ if var.global_alertmanager }{{{ range secrets "secret/default/alertmanager/receivers/heartbeats" }}}{{{ $hb := . }}}- name: 'heartbeat_{{{ $hb }}}'
  webhook_configs:
  - url: '{{{ with secret (printf "secret/default/alertmanager/receivers/heartbeats/%s" $hb) }}}{{{ .Data.data.url }}}{{{ end }}}'
    send_resolved: false
{{{ end }}}%{ endif }- name: slack_pages
  slack_configs:
    - channel: '#pages'
      api_url: '{{{ with secret "secret/default/alertmanager/receivers/slack" }}}{{{ .Data.data.slack_pages_webhook }}}{{{ end }}}'
      send_resolved: true
      title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] ({{ or .CommonLabels.alertname "Multiple Alert Types" }}) in %{ if var.global_alertmanager }{{ .CommonLabels.environment }} (GLOBAL)%{ else }${var.dc}%{ endif }'
      text: |-
        {{ if eq .CommonLabels.severity "severe" }}{{ if eq .Status "firing" }}<!here> - PAGE{{ if .CommonLabels.page }}{{ if ne .CommonLabels.page "true" }}-CANDIDATE{{ end }}{{ else }}-CANDIDATE{{ end }}{{ end }}{{ end }}{{ range .Alerts }}
        *{{ index .Labels "alertname" }}* {{ index .Labels "datacenter" }}{{- if .Annotations.summary }}: *{{ .Annotations.summary }}* {{- end }}{{ if eq .Status "firing" }} - {{ if .Annotations.alert_url }}{{ .Annotations.alert_url }}{{ end }}{{ end }}
        {{- end }}
%{ endif }
EOH
      }

      resources {
        cpu    = 500
        memory = 500
      }

      shutdown_delay = "10s"
      service {
        name = "alertmanager%{ if var.global_alertmanager }-global%{ endif }"
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

      dynamic "service" {
        for_each = var.global_alertmanager ? ["alertmanager-global-cluster"] : []
        content {
          name = service.value
          port = "cluster"
        }
      }
    }
  }
}