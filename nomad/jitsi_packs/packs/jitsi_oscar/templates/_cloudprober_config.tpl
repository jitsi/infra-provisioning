[[ define "cloudprober-config" ]]
[[ if var "enable_site_ingress" . -]]
# probes site ingress health from this datacenter
probe {
  name: "site"
  type: HTTP
  targets {
    host_names: "[[ var "domain" . ]]"
  }
  interval_msec: 5000
  timeout_msec: 2000

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
    command: "/bin/oscar_haproxy_probe.sh"
  }
  interval_msec: 5000
  timeout_msec: 2000
}
[[ end -]]
[[ if var "enable_autoscaler" . -]]
# probes autoscaler health in the local datacenter
probe {
  name: "autoscaler"
  type: HTTP
  targets {
    host_names: "[[ var "environment" . ]]-[[ var "oracle_region" . ]]-autoscaler.[[ var "top_level_domain" . ]]"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/health?deep=true"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 2000
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
  timeout_msec: 2000
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
    command: "/bin/oscar_coturn_probe.sh @target@"
  }
  interval_msec: 60000
  timeout_msec: 2000
}
[[ end -]]
[[ if var "enable_shard" . -]]
# probes health of all shards in all datacenters using public IP
probe {
  name: "shard"
  type: HTTP
  targets {
    {{ $shard_count := 0 }}
    {{ range $dc := datacenters }}{{ $dc_shards := print "signal-sidecar@" $dc }}{{ range $shard := service $dc_shards -}}
      {{ $shard_count = add $shard_count 1 }}
    endpoint {
      name: "{{ .ServiceMeta.shard }}"
      url: "http://{{ .Address }}:{{ .Port }}/about/health"
    }
    {{ end }}{{ end }}
    {{ if eq $shard_count 0 -}}
    host_names: ""
    {{ end }}
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }

  interval_msec: 5000
  timeout_msec: 2000
}

[[ end -]]
[[ if var "enable_skynet" . -]]
# probes skynet health
probe {
  name: "skynet"
  type: HTTP
  targets {
    host_names: "[[ var "skynet_hostname" . ]]"
  }
  interval_msec: 5000
  timeout_msec: 2000

  http_probe {
    protocol: HTTPS
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
}
[[ end -]]
[[ if var "enable_whisper" . -]]
# probes whisper health
probe {
  name: "whisper"
  type: HTTP
  targets {
    host_names: "[[ var "whisper_hostname" . ]]"
  }
  interval_msec: 5000
  timeout_msec: 2000

  http_probe {
    protocol: HTTPS
    relative_url: "/healthz"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
}
[[ end -]]
[[ if var "enable_custom_https" . -]]
probe {
  name: "https"
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
  interval_msec: 5000
  timeout_msec: 2000
}
[[ end -]]
[[ if var "enable_loki" . -]]
# probes loki health in the local datacenter
probe {
  name: "loki"
  type: HTTP
  targets {
    host_names: "{{ range $index, $service := service "loki"}}{{ if gt $index 0 }},{{ end }}{{ .Address }}:{{.Port}}{{ end }}"
  }
  http_probe {
    relative_url: "/ready"
  }
  validator {
      name: "status_code_2xx"
      http_validator {
          success_status_codes: "200-299"
      }
  }
  interval_msec: 60000
  timeout_msec: 2000
}
[[ end -]]

[[ end -]]