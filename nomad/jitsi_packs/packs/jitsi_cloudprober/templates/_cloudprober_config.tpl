[[ define "cloudprober-config" ]]

surfacer {
  type: PROMETHEUS
  export_as_gauge: true
}

# add variables for default_cloudprober_severity and default_cloudprober_team, and apply them to all non-custom probes

[[ if var "enable_site_ingress" . -]]
# probes site ingress health from this datacenter
probe {
  name: "site"
  type: HTTP
  targets {
    host_names: "[[ var "domain" . ]]"
  }
  interval_msec: 10000
  timeout_msec: 5000
  latency_unit: "ms"
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
}

[[ end -]]
[[ if var "enable_haproxy_region" . -]]
# probe to validate that the ingress haproxy reached is in the local datacenter
probe {
  name: "haproxy_region"
  type: EXTERNAL
  targets {
    host_names: "[[ var "domain" . ]]"
  }
  external_probe {
    mode: ONCE 
    command: "/bin/cloudprober_haproxy_probe.sh"
  }
  interval_msec: 10000
  timeout_msec: 5000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_autoscaler" . -]]
# probes autoscaler health in the local datacenter
probe {
  name: "autoscaler"
  type: HTTP
  targets {
    host_names: "{{ range $index, $service := service "autoscaler"}}{{ if gt $index 0 }},{{ end }}{{ .Address }}:{{ if .ServiceMeta.health_port}}{{ .ServiceMeta.health_port }}{{ else }}{{ .ServiceMeta.metrics_port }}{{ end }}{{ end }}"
  }
  http_probe {
    relative_url: "/health?deep=true"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_wavefront_proxy" . -]]
# probes wavefront-proxy health in the local datacenter
probe {
  name: "wfproxy"
  type: HTTP
  targets {
    host_names: "[[ var "environment" . ]]-[[ var "oracle_region" . ]]-wfproxy.[[ var "top_level_domain" . ]]"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/status"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_coturn" . -]]
# probes coturn health in the local datacenter using public IP
probe {
  name: "coturn"
  type: EXTERNAL
  targets {
    host_names: "{{ range $index, $service := service "coturn"}}{{ if gt $index 0 }},{{ end }}{{ .ServiceMeta.public_ip }}{{ end }}"
  }
  external_probe {
    mode: ONCE 
    command: "/bin/cloudprober_coturn_probe.sh @target@"
  }
  interval_msec: 20000
  timeout_msec: 5000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_shard" . -]]
# probes health of all shards via their signal-sidecars, in all datacenters
probe {
  name: "shard"
  type: HTTP

  targets {
    {{ $shard_count := 0 -}}
    {{ range $dc := datacenters -}}{{ $dc_shards := print "signal@" $dc -}}{{ range $shard := service $dc_shards -}}
    {{ $shard_count = add $shard_count 1 -}}
    endpoint {
      name: "{{ .ServiceMeta.shard }}"
      url: "http://{{ .Address }}:{{ if .ServiceMeta.signal_sidecar_http_port }}{{ .ServiceMeta.signal_sidecar_http_port }}{{ else }}6000{{ end }}/about/health"
    }
    {{ end }}{{ end -}}
    {{ if eq $shard_count 0 -}}
    host_names: ""
    {{- end }}
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 10000
  timeout_msec: 5000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_shard_latency" . -]]
# measures between datacenters using shard _health endpoints
probe {
  name: "latency"
  type: HTTP

  targets {
    {{ $shard_count := 0 -}}
    {{ range $dc := datacenters -}}{{ $dc_shards := print "signal@" $dc -}}{{ range $shard := service $dc_shards -}}
    {{ if ne .ServiceMeta.http_backend_port "443" }}{{ $shard_count = add $shard_count 1 -}}
    endpoint {
      name: "{{ .ServiceMeta.shard }}"
      url: "http://{{ .Address }}:{{ if .ServiceMeta.http_backend_port }}{{ .ServiceMeta.http_backend_port }}{{ else }}80{{ end }}/_health"
    }
    {{ end }}{{ end }}{{ end -}}
    {{ if eq $shard_count 0 -}}
    host_names: ""
    {{- end }}
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 10000
  timeout_msec: 10000
  latency_unit: "ms"
}

# measures between datacenters using shard _health endpoints
probe {
  name: "latency_https"
  type: HTTP

  targets {
    {{ $shard_count := 0 -}}
    {{ range $dc := datacenters -}}{{ $dc_shards := print "signal@" $dc -}}{{ range $shard := service $dc_shards -}}
    {{ if eq .ServiceMeta.http_backend_port "443" }}{{ $shard_count = add $shard_count 1 -}}
    endpoint {
      name: "{{ .ServiceMeta.shard }}"
      url: "https://{{ .Address }}/_health"
    }
    {{ end }}{{ end }}{{ end -}}
    {{ if eq $shard_count 0 -}}
    host_names: ""
    {{- end }}
  }
  http_probe {
    protocol: HTTPS
    tls_config {
        disable_cert_validation: true
    }
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 10000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_prometheus" . -]]
# probes prometheus health in all datacenters
probe {
  name: "prometheus"
  type: HTTP
  targets {
    host_names: "{{ range $dcidx, $dc := datacenters -}}{{ if ne $dcidx 0 }},{{ end }}{{ $dc }}-prometheus.[[ var "top_level_domain" . ]]{{ end }}"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/-/healthy"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_alertmanager" . -]]
# probes alertmanager health in all datacenters
probe {
  name: "alertmanager"
  type: HTTP
  targets {
    host_names: "{{ range $dcidx, $dc := datacenters -}}{{ if ne $dcidx 0 }},{{ end }}{{ $dc }}-alertmanager.[[ var "top_level_domain" . ]]{{ end }}"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/-/healthy"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_cloudprober" . -]]
# probes cloudprober health in all other datacenters
probe {
  name: "cloudprober"
  type: HTTP
  targets {
    host_names: "{{ range $dcidx, $dc := datacenters -}}{{ if ne $dcidx 0 }}{{ if ne $dcidx 1 }},{{ end }}{{ $dc }}-cloudprober.[[ var "top_level_domain" . ]]{{ end }}{{ end }}"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/health"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}

[[ end -]]
[[ if var "enable_custom_https" . -]]
probe {
  name: "custom"
  type: HTTP
  targets {
      [[ var "custom_https_targets" . ]]
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 20000
  timeout_msec: 10000
  latency_unit: "ms"
  additional_label {
    key: "severity"
    value: "@target.label.severity@"
  }
  additional_label {
    key: "team"
    value: "@target.label.team@"
  }
}

[[ end -]]
[[ if var "enable_loki" . -]]
# probes loki health in the local datacenter
probe {
  name: "loki"
  type: HTTP
  targets {
    host_names: "[[ var "environment" . ]]-[[ var "oracle_region" . ]]-loki.[[ var "top_level_domain" . ]]"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/ready"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}
[[ end -]]
[[ if var "enable_vault" . -]]
# probes vault health in the local datacenter
probe {
  name: "vault"
  type: HTTP
  targets {
    host_names: "[[ var "environment" . ]]-[[ var "oracle_region" . ]]-vault.[[ var "top_level_domain" . ]]"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/v1/sys/health"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299,429"
      }
  }
  interval_msec: 60000
  timeout_msec: 10000
  latency_unit: "ms"
}
[[ end -]]

[[ end -]]