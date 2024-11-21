job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [ "[[ var "datacenter" . ]]" ]
  type = "service"

  meta {
    domain = "[[ env "CONFIG_domain" ]]"
    shard = "[[ env "CONFIG_shard" ]]"
    release_number = "[[ env "CONFIG_release_number" ]]"
    environment = "[[ env "CONFIG_environment" ]]"
    octo_region = "[[ env "CONFIG_octo_region" ]]"
    cloud_provider = "[[ env "CONFIG_cloud_provider" ]]"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

[[ $VNODE_COUNT := (or (var "visitors_count" .) 0) ]]
[[ $STS_PORT := (or (var "sts_port" .) 5269) ]]
[[ $VNODE_STS_PORT := (or (var "vnode_sts_port" .) 7269) ]]
[[ $VNODE_CLIENT_PORT := (or (var "vnode_client_port" .) 7222) ]]

  group "signal" {
    count = 1

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "[[ env "CONFIG_pool_type" ]]"
    }

    network {
      mode = "bridge"
      port "http" {
        to = 80
      }
      port "nginx-status" {
        to = 888
      }
      port "web-nginx-prometheus-exporter" {
        to = 9113
      }
      port "prosody-http" {
      }
      port "signal-sidecar-agent" {
      }
      port "signal-sidecar-http" {
      }
      port "prosody-client" {
      }
[[- if eq (or (env "CONFIG_prosody_shard_mitm_enabled") "false") "true" ]]
      port "prosody-mitm" {
      }
[[- end ]]
[[- if eq (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
      port "prosody-jvb-client" {
      }
      port "prosody-jvb-http" {
      }
[[- end ]]
      port "jicofo-http" {
        to = 8888
      }
[[ if gt $VNODE_COUNT 0 -]]

[[ range $index, $i := split " "  (seq 0 ((sub $VNODE_COUNT 1)|int)) ]]
      port "prosody-vnode-[[ $i ]]-http" {
      }
[[ end ]]
[[ end ]]

    }

    service {
      name = "signal"
      tags = [
        "[[ env "CONFIG_domain" ]]",
        "shard-[[ env "CONFIG_shard" ]]",
        "release-[[ env "CONFIG_release_number" ]]"
      ]

      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        shard_id = "[[ env "CONFIG_shard_id" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
        http_backend_port = "${NOMAD_HOST_PORT_http}"
        prosody_http_ip = "${NOMAD_IP_prosody_http}"
        nginx_status_ip = "${NOMAD_IP_nginx_status}"
        nginx_status_port = "${NOMAD_HOST_PORT_nginx_status}"
        nginx_metrics_port = "${NOMAD_HOST_PORT_web_nginx_prometheus_exporter}"
        prosody_client_ip = "${NOMAD_IP_prosody_client}"
        prosody_http_port = "${NOMAD_HOST_PORT_prosody_http}"
        prosody_client_port = "${NOMAD_HOST_PORT_prosody_client}"
[[- if eq (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
        prosody_jvb_client_port = "${NOMAD_HOST_PORT_prosody_jvb_client}"
[[- end ]]
        signal_sidecar_agent_port = "${NOMAD_HOST_PORT_signal_sidecar_agent}"
        signal_sidecar_http_ip = "${NOMAD_IP_signal_sidecar_http}"
        signal_sidecar_http_port = "${NOMAD_HOST_PORT_signal_sidecar_http}"
        signal_version = "[[ env "CONFIG_signal_version" ]]"
        nomad_allocation = "${NOMAD_ALLOC_ID}"
      }

      port = "http"
[[- if or (eq (env "CONFIG_prosody_meet_webhooks_enabled") "true") (eq (env "CONFIG_prosody_enable_muc_events" ) "true") (ne (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true") ]]
      connect {
        sidecar_service {
          proxy {
[[- if ne (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
            upstreams {
              destination_name = "prosody-brewery"
              local_bind_port  = 6222
            }
[[- end ]]
[[- if or (eq (env "CONFIG_prosody_meet_webhooks_enabled") "true") (eq (env "CONFIG_prosody_enable_muc_events" ) "true") ]]
            upstreams {
              destination_name = "prosody-egress"
              local_bind_port  = 9880
            }
[[- end ]]
          }
        }
      }
[[- end ]]

    }

    service {
      name = "shard-web"
      tags = [
        "[[ env "CONFIG_domain" ]]",
        "shard-[[ env "CONFIG_shard" ]]",
        "release-[[ env "CONFIG_release_number" ]]",
[[ if (var "fabio_domain_enabled" .) ]]
        "urlprefix-[[ env "CONFIG_domain" ]]/",
[[ end ]]
        "urlprefix-/[[ env "CONFIG_shard" ]]/",
        "urlprefix-/v1/_cdn/[[ env "CONFIG_jitsi_meet_cdn_prefix" ]][[ env "CONFIG_web_tag" ]]/",
        "ip-${attr.unique.network.ip-address}"
      ]
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        shard_id = "[[ env "CONFIG_shard_id" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
        nomad_allocation = "${NOMAD_ALLOC_ID}"
        metrics_port = "${NOMAD_HOST_PORT_web_nginx_prometheus_exporter}"
      }

      port = "http"

      check {
        name     = "health"
        type     = "http"
        path     = "/nginx_status"
        port     = "nginx-status"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "jicofo"
      tags = ["[[ env "CONFIG_shard" ]]", "[[ env "CONFIG_environment" ]]","ip-${attr.unique.network.ip-address}"]
      port = "jicofo-http"

      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
      }
    }

    service {
      name = "prosody-http"
      tags = ["[[ env "CONFIG_shard" ]]","ip-${attr.unique.network.ip-address}"]
      port = "prosody-http"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/http-bind"
        port     = "prosody-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

[[- if eq (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
    service {
      name = "prosody-jvb-http"
      tags = ["[[ env "CONFIG_shard" ]]","ip-${attr.unique.network.ip-address}"]
      port = "prosody-jvb-http"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/metrics"
        port     = "prosody-jvb-http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    service {

      name = "prosody-jvb-client"
      tags = ["[[ env "CONFIG_shard" ]]"]
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
      }

      port = "prosody-jvb-client"

      check {
        name     = "health"
        type     = "http"
        path     = "/metrics"
        port     = "prosody-jvb-http"
        interval = "10s"
        timeout  = "2s"
      }
    }
[[- end ]]
    service {
      name = "signal-sidecar"
      tags = ["[[ env "CONFIG_shard" ]]","ip-${attr.unique.network.ip-address}","urlprefix-/[[ env "CONFIG_shard" ]]/about/health strip=/[[ env "CONFIG_shard" ]]"]
      port = "signal-sidecar-http"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/health"
        port     = "signal-sidecar-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {

      name = "prosody-client"
      tags = ["[[ env "CONFIG_shard" ]]"]

      port = "prosody-client"

      check {
        name = "health"
        type = "http"
        path = "/http-bind"
        port = "prosody-http"
        interval = "10s"
        timeout = "2s"
      }
    }

[[ if gt $VNODE_COUNT 0 -]]
[[ range $index, $i := split " "  (seq 0 ((sub $VNODE_COUNT 1)|int)) ]]
    service {
      name = "prosody-vnode"
      tags = ["[[ env "CONFIG_shard" ]]","v-[[ $i ]]","ip-${attr.unique.network.ip-address}"]
      port = "prosody-vnode-[[ $i ]]-http"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        shard = "[[ env "CONFIG_shard" ]]"
        release_number = "[[ env "CONFIG_release_number" ]]"
        prosody_client_port = "[[ add $VNODE_CLIENT_PORT $i ]]"
        environment = "${meta.environment}"
        vindex = "[[ $i ]]"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/http-bind"
        port     = "prosody-vnode-[[ $i ]]-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "prosody-vnode-[[ $i ]]" {
      driver = "docker"

      vault {
        change_mode = "noop"

      }

      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/prosody:[[ env "CONFIG_prosody_tag" ]]"
        ports = ["prosody-vnode-[[ $i ]]-http"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom","local/config:/config"]
      }

      env {
        PROSODY_MODE="visitors"
[[ template "common-env" . ]]
        ENABLE_VISITORS="true"
        ENABLE_AUTH="true"
[[- if eq (env "CONFIG_prosody_enable_guest_auth") "true" ]]
        ENABLE_GUESTS="true"
[[- end ]]
#        LOG_LEVEL="debug"
        PROSODY_VISITOR_INDEX="[[ $i ]]"
[[ if or (eq (or (env "CONFIG_jigasi_vault_enabled") "false") "true") (env "CONFIG_jigasi_shared_secret") -]]
        PROSODY_VISITORS_S2S_VHOSTS="jigasia.[[ env "CONFIG_domain" ]]"
[[ end]]
        PROSODY_C2S_LIMIT="512kb/s"
        PROSODY_DISABLE_S2S_LIMIT="1"
        PROSODY_ENABLE_RATE_LIMITS="1"
        PROSODY_RATE_LIMIT_ALLOW_RANGES="[[ env "CONFIG_prosody_rate_limit_allow_ranges" ]]"
        PROSODY_REGION_NAME="[[ env "CONFIG_octo_region" ]]"
        VISITORS_MAX_VISITORS_PER_NODE=
          [[- if and (env "CONFIG_prosody_visitors_muc_max_occupants") (ne (env "CONFIG_prosody_visitors_muc_max_occupants") "false") -]]
            [[ env "CONFIG_prosody_visitors_muc_max_occupants" ]]
          [[- else -]]
            250
        [[- end ]]
        TURN_TRANSPORT="udp"
      }
[[ template "prosody_artifacts" . ]]

      template {
        data = <<EOF
#
# prosody vnode configuration options
#
XMPP_SERVER=localhost
XMPP_SERVER_S2S_PORT=[[ $STS_PORT ]]
PROSODY_HTTP_PORT={{ env "NOMAD_HOST_PORT_prosody_vnode_[[ $i ]]_http" }}
PROSODY_S2S_PORT=[[ add $VNODE_STS_PORT $i ]]

# our networks and cloudflare ip-ranges (cloudflare ranges come from https://www.cloudflare.com/en-gb/ips/)
PROSODY_TRUSTED_PROXIES="127.0.0.1,::1,10.0.0.0/8,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17,2400:cb00::/32,2405:8100::/32,2405:b500::/32,2606:4700::/32,2803:f800::/32,2a06:98c0::/29,2c0f:f248::/32"

GLOBAL_CONFIG="console_ports={ 7582+[[ $i ]] };\nstatistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\n
[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" -]]
muc_prosody_egress_url = \"http://localhost:9880/v1/events\";\nmuc_prosody_egress_fallback_url = \"[[ env "CONFIG_prosody_egress_fallback_url" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_jaas_actuator_url") -]]
muc_prosody_jaas_actuator_url = \"[[ env "CONFIG_prosody_jaas_actuator_url" ]]\";\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_meet_ban_auth_enabled") "true" -]]
muc_prosody_jitsi_access_manager_url = \"[[ env "CONFIG_jitsi_access_manager_url" ]]\";\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_enable_muc_events") "true" -]]
asap_key_path = \"/secrets/asap.key\";\nasap_key_id = \"{{ with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.key_id }}{{ end }}\";\nasap_issuer = \"[[ or (env "CONFIG_prosody_asap_issuer") "jitsi" ]]\";\nasap_audience = \"[[ or (env "CONFIG_prosody_asap_audience") "jitsi" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_conference_info_url") -]]
muc_conference_info_url = "[[ env "CONFIG_prosody_conference_info_url" ]]\";\n
[[- if (env "CONFIG_prosody_password_public_key_repo_url") -]]
prosody_password_public_key_repo_url = \"[[ env "CONFIG_prosody_password_public_key_repo_url" ]]\";\n
[[- end -]]
[[- end -]]
"
GLOBAL_MODULES="admin_telnet,http_openmetrics,log_ringbuffer,firewall,muc_census,secure_interfaces,external_services,turncredentials_http[[ if eq (env "CONFIG_prosody_mod_measure_stanza_counts") "true" ]],measure_stanza_counts[[ end ]][[ if eq (env "CONFIG_prosody_enable_password_preset" ) "true" ]],muc_password_preset[[ end ]]"

XMPP_CONFIG="
[[- if ne (or (env "CONFIG_prosody_cache_keys_url") "false") "false" -]]
cache_keys_url=\"[[ env "CONFIG_prosody_cache_keys_url" ]]\",
[[- end -]]
[[- if env "CONFIG_prosody_vpaas_public_key_repo_url" -]]
vpaas_asap_key_server = \"[[ env "CONFIG_prosody_vpaas_public_key_repo_url" ]]\",
[[- end -]]
"
XMPP_MODULES="jiconop"
XMPP_MUC_MODULES="
[[- if eq (env "CONFIG_prosody_meet_auth_vpaas_enabled") "true" ]]muc_auth_vpaas,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_permissions_vpaas_enabled") "true" ]]muc_permissions_vpaas,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_ban_auth_enabled") "true" ]]muc_auth_ban,[[ end -]]
[[- if eq (env "CONFIG_prosody_enable_muc_events" ) "true" -]]muc_events,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" -]]muc_visitors_webhooks[[- end -]]"
XMPP_PORT=[[ add $VNODE_CLIENT_PORT $i ]]

EOF

        destination = "local/prosody.env"
        env = true
      }

      template {
        data = <<EOF
{{- with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/asap.key"
      }

      template {
        data = <<EOH

[[ if or (eq (or (env "CONFIG_jigasi_vault_enabled") "false") "true") (env "CONFIG_jigasi_shared_secret") -]]
VirtualHost "jigasia.v[[ $i ]].meet.jitsi"
    modules_enabled = {
      "smacks";
    }
    authentication = "jitsi-shared-secret"
    smacks_max_old_sessions = 2000;
[[- if eq (or (env "CONFIG_jigasi_vault_enabled") "false") "true" ]]
{{- with secret "secret/[[ env "CONFIG_environment" ]]/jigasi/xmpp" }}
    shared_secret = "{{ .Data.data.password }}"
{{- end }}
[[- else ]]
    shared_secret = "[[ env "CONFIG_jigasi_shared_secret" ]]"
[[- end ]]

[[- end ]]
EOH
        destination = "local/config/conf.d/other-domains.cfg.lua"
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_prosody_vnode_cpu") "200" ]]
        memory    = [[ or (env "CONFIG_nomad_prosody_vnode_memory") "512" ]]
      }
    }

[[ end -]]
[[ end -]]

    task "signal-sidecar" {
      driver = "docker"
      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/signal-sidecar:latest"
        ports = ["signal-sidecar-agent","signal-sidecar-http"]
      }

      env {
        CENSUS_POLL = true
        CENSUS_REPORTS = true
        CONSUL_SECURE = false
        CONSUL_PORT=8500
        CONSUL_STATUS = true
        CONSUL_REPORTS = true
        CONSUL_STATUS_KEY = "shard-states/[[ env "CONFIG_environment" ]]/[[ env "CONFIG_shard" ]]"
        CONSUL_REPORT_KEY = "signal-report/[[ env "CONFIG_environment" ]]/[[ env "CONFIG_shard" ]]"
      }
      template {
          data = <<EOF
CONSUL_HOST={{ env "attr.unique.network.ip-address" }}
HTTP_PORT={{ env "NOMAD_HOST_PORT_signal_sidecar_http" }}
TCP_PORT={{ env "NOMAD_HOST_PORT_signal_sidecar_agent" }}
CENSUS_HOST={{ env "NOMAD_META_domain" }}
JICOFO_ORIG=http://localhost:8888
PROSODY_ORIG=http://localhost:{{ env "NOMAD_HOST_PORT_prosody_http" }}
EOF

        destination = "local/signal-sidecar.env"
        env = true
      }
      resources {
        cpu    = [[ or (env "CONFIG_nomad_signal_sidecar_cpu") "100" ]]
        memory    = [[ or (env "CONFIG_nomad_signal_sidecar_memory") "300" ]]
      }
    }

    task "prosody" {
      vault {
        change_mode = "noop"
        
      }
      driver = "docker"

      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/prosody:[[ env "CONFIG_prosody_tag" ]]"
        ports = ["prosody-http","prosody-client"]
        volumes = [
          "local/patch-prosody.sh:/etc/cont-init.d/08-patch-prosody",
          "local/prosody-plugins-custom:/prosody-plugins-custom",
          "local/config:/config",
        ]
      }

      env {
[[ template "common-env" . ]]
        ENABLE_VISITORS = "[[ env "CONFIG_visitors_enabled" ]]"
        ENABLE_LOBBY="1"
        ENABLE_AV_MODERATION="1"
        ENABLE_BREAKOUT_ROOMS="1"
        ENABLE_AUTH="1"
[[- if eq (env "CONFIG_prosody_enable_guest_auth") "true" ]]
        ENABLE_GUESTS="true"
[[- end ]]
        ENABLE_END_CONFERENCE="0"
        PROSODY_ENABLE_RATE_LIMITS="1"
        PROSODY_RATE_LIMIT_ALLOW_RANGES="[[ env "CONFIG_prosody_rate_limit_allow_ranges" ]]"
        PROSODY_C2S_LIMIT="512kb/s"
        PROSODY_DISABLE_S2S_LIMIT="1"
        PROSODY_RATE_LIMIT_SESSION_RATE="2000"
        TURN_TRANSPORT="udp"
        JWT_ALLOW_EMPTY="[[ env "CONFIG_prosody_token_allow_empty" ]]"
        JWT_ENABLE_DOMAIN_VERIFICATION="true"
        JWT_ACCEPTED_ISSUERS="[[ env "CONFIG_jwt_accepted_issuers" ]]"
        JWT_ACCEPTED_AUDIENCES="[[ env "CONFIG_jwt_accepted_audiences" ]]"
        JWT_ASAP_KEYSERVER="[[ env "CONFIG_prosody_public_key_repo_url" ]]"
        JWT_APP_ID="jitsi"
[[- if ne (env "CONFIG_prosody_muc_max_occupants") "false"]]
        MAX_PARTICIPANTS=[[ env "CONFIG_prosody_muc_max_occupants" ]]
[[- end ]]
      }
[[ template "prosody_artifacts" . ]]
      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
sed -i 's/"debug", "Client XML parse error/"info", "Client XML parse error/' /usr/lib/prosody/modules/mod_c2s.lua
EOF
        destination = "local/patch-prosody.sh"
        perms = "755"
      }

[[ if eq (or (env "CONFIG_jigasi_vault_enabled") "true") "true" ]]
      template {
        data = <<EOF
#!/usr/bin/with-contenv bash
PROSODY_CFG="/config/prosody.cfg.lua"

. /secrets/jigasi_xmpp
prosodyctl --config $PROSODY_CFG register $JIGASI_XMPP_USER $XMPP_AUTH_DOMAIN $JIGASI_XMPP_PASSWORD

EOF
        destination = "local/jigasi_xmpp.sh"
        perms = "755"
      }
      template {
        data = <<EOF
{{- with secret "secret/[[ env "CONFIG_environment" ]]/jigasi/xmpp" }}
JIGASI_XMPP_USER="{{ .Data.data.user }}"
JIGASI_XMPP_PASSWORD="{{ .Data.data.password }}"
{{- end }}
EOF
        destination = "secrets/jigasi_xmpp"
        change_mode = "script"
        change_script {
          command       = "/local/jigasi_xmpp.sh"
          fail_on_error = false
        }
        env = true
      }
[[ end ]]
      template {
        data = <<EOF
{{- with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.private_key }}{{ end -}}
EOF
        destination = "secrets/asap.key"
      }

      template {
        data = <<EOF
VISITORS_XMPP_SERVER=[[ range $index, $i := split " "  (seq 0 ((sub $VNODE_COUNT 1)|int)) ]][[ if gt ($i|int) 0 ]],[[ end ]]localhost:[[ add $VNODE_STS_PORT $i ]][[ end ]]  
PROSODY_HTTP_PORT={{ env "NOMAD_HOST_PORT_prosody_http" }}
PROSODY_S2S_PORT=[[ $STS_PORT ]]

#
# prosody main configuration options
#

GLOBAL_CONFIG="console_ports={ 5582 };\nstatistics = \"internal\"\nstatistics_interval = \"manual\"\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\ntoken_verification_allowlist = { \"recorder.[[ env "CONFIG_domain" ]]\" };\nmuc_mapper_log_not_allowed_errors = true;\n
[[- if (env "CONFIG_prosody_meet_chat_history_url") -]]
muc_chat_history_url = \"[[ env "CONFIG_prosody_meet_chat_history_url" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_jaas_actuator_url") -]]
muc_prosody_jaas_actuator_url = \"[[ env "CONFIG_prosody_jaas_actuator_url" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_meet_speaker_stats_url") -]]
muc_speaker_stats_url = \"[[ env "CONFIG_prosody_meet_speaker_stats_url" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_meet_transcriptions_url") -]]
muc_transcriptions_url = \"[[ env "CONFIG_prosody_meet_transcriptions_url" ]]\";\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_meet_ban_auth_enabled") "true" -]]
muc_prosody_jitsi_access_manager_url = \"[[ env "CONFIG_jitsi_access_manager_url" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_conference_info_url") -]]
muc_conference_info_url = "[[ env "CONFIG_prosody_conference_info_url" ]]\";\n
[[- if (env "CONFIG_prosody_password_public_key_repo_url") -]]
prosody_password_public_key_repo_url = \"[[ env "CONFIG_prosody_password_public_key_repo_url" ]]\";\n
[[- end -]]
[[- end -]]
[[- if (env "CONFIG_prosody_visitors_queue_service_url") -]]
visitors_queue_service = \"[[ env "CONFIG_prosody_visitors_queue_service_url" ]]\";\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_disable_required_room_claim") "true" -]]
asap_require_room_claim = false;\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_enable_password_waiting_for_host") "true" -]]
enable_password_waiting_for_host = true;\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_enable_muc_events") "true" -]]
asap_key_path = \"/secrets/asap.key\";\nasap_key_id = \"{{ with secret "secret/[[ env "CONFIG_environment" ]]/asap/server" }}{{ .Data.data.key_id }}{{ end }}\";\nasap_issuer = \"[[ or (env "CONFIG_prosody_asap_issuer") "jitsi" ]]\";\nasap_audience = \"[[ or (env "CONFIG_prosody_asap_audience") "jitsi" ]]\";\n
[[- end -]]
[[- if (env "CONFIG_prosody_amplitude_api_key") -]]
amplitude_api_key = \"[[ env "CONFIG_prosody_amplitude_api_key" ]]\";\n
[[- end -]]
debug_traceback_filename = \"traceback.txt\";\nc2s_stanza_size_limit = 512*1024;\ncross_domain_websocket =  true;\ncross_domain_bosh = false;\nbosh_max_inactivity = 60;\n
[[- if (env "CONFIG_prosody_limit_messages") -]]
muc_limit_messages_count = [[ env "CONFIG_prosody_limit_messages" ]];\nmuc_limit_messages_check_token = [[ env "CONFIG_prosody_limit_messages_check_token" ]];\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" -]]
muc_prosody_egress_url = \"http://localhost:9880/v1/events\";\nmuc_prosody_egress_fallback_url = \"[[ env "CONFIG_prosody_egress_fallback_url" ]]\";\n
[[- end -]]
[[- if eq (env "CONFIG_prosody_muc_require_token_for_moderation") "true" -]]
token_verification_require_token_for_moderation = true;\n
[[- end -]]
"

PROSODY_LOG_CONFIG="
[[- if eq (env "CONFIG_prosody_enable_wait_for_host") "true" -]]
{ levels = { \"audit\" }, to = \"console\", timestamps = \"%Y-%m-%d %X\"};
[[- end -]]
[[- if env "CONFIG_prosody_mod_log_ringbuffer_size" -]]
{level = \"debug\", to = \"ringbuffer\",size = [[ or (env "CONFIG_prosody_mod_log_ringbuffer_size") "1014*1024*4" ]], filename_template = \"traceback.txt\", event = \"debug_traceback/triggered\";};
[[- end -]]
"

# our networks and cloudflare ip-ranges (cloudflare ranges come from https://www.cloudflare.com/en-gb/ips/)
PROSODY_TRUSTED_PROXIES="127.0.0.1,::1,10.0.0.0/8,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,104.16.0.0/13,104.24.0.0/14,108.162.192.0/18,131.0.72.0/22,141.101.64.0/18,162.158.0.0/15,172.64.0.0/13,173.245.48.0/20,188.114.96.0/20,190.93.240.0/20,197.234.240.0/22,198.41.128.0/17,2400:cb00::/32,2405:8100::/32,2405:b500::/32,2606:4700::/32,2803:f800::/32,2a06:98c0::/29,2c0f:f248::/32"

GLOBAL_MODULES="admin_telnet,http_openmetrics,
[[- if eq (env "CONFIG_prosody_enable_password_preset" ) "true" ]]muc_password_preset,[[ end ]]
[[- if env "CONFIG_prosody_mod_log_ringbuffer_size" ]]log_ringbuffer,debug_traceback,[[ end -]]
[[- if eq (env "CONFIG_prosody_mod_measure_stanza_counts") "true" ]]measure_stanza_counts,[[ end -]]
[[- if eq (env "CONFIG_prosody_enable_presence_identity") "true" ]]presence_identity,[[ end -]]
muc_census,muc_end_meeting,secure_interfaces,external_services,turncredentials_http"

XMPP_MODULES="
[[- if eq (env "CONFIG_prosody_enable_filter_iq_jibri") "true" ]]filter_iq_jibri,[[ end -]]
[[- if eq (env "CONFIG_prosody_enable_filter_iq_rayo") "true" ]]filter_iq_rayo,[[ end -]]
[[- if eq (env "CONFIG_prosody_enable_persistent_lobby") "true" ]]persistent_lobby,[[ end -]]
jiconop,system_chat_message"

[[- if eq (env "CONFIG_prosody_enable_token_room_verification") "false" ]]
# hack to avoid token_verification when firebase auth is on
JWT_TOKEN_AUTH_MODULE=muc_hide_all
[[- end ]]

XMPP_CONFIGURATION="
[[- if ne (or (env "CONFIG_prosody_cache_keys_url") "false") "false" -]]
cache_keys_url=\"[[ env "CONFIG_prosody_cache_keys_url" ]]\",
[[- end -]]
[[- if env "CONFIG_prosody_vpaas_public_key_repo_url" -]]
vpaas_asap_key_server = \"[[ env "CONFIG_prosody_vpaas_public_key_repo_url" ]]\",
[[- end -]]
[[- if ne (or (env "CONFIG_prosody_recording_rate_per_minute_per_ip") "false") "false" -]]
max_number_ip_attempts_per_minute=[[ env "CONFIG_prosody_recording_rate_per_minute_per_ip" ]],
[[- end -]]
shard_name=\"[[ env "CONFIG_shard" ]]\",region_name=\"{{ env "meta.cloud_region" }}\",release_number=\"[[ env "CONFIG_release_number" ]]\",max_number_outgoing_calls=[[ or (env "CONFIG_prosody_max_number_outgoing_calls") "3" ]]"
XMPP_MUC_CONFIGURATION="
[[- if env "CONFIG_muc_moderated_subdomains" -]]
allowners_moderated_subdomains = {\n 
  [[- range (env "CONFIG_muc_moderated_subdomains" | split ",") -]]
    \"[[ . ]]\";\n
  [[- end -]]
},
[[- end -]]
[[- if env "CONFIG_muc_moderated_rooms" -]]
allowners_moderated_rooms = {\n
  [[- range (env "CONFIG_muc_moderated_rooms" | split ",") -]]
    \"[[ . ]]\";\n
  [[- end -]]
}
[[- end -]]
"

XMPP_MUC_MODULES="
[[- if eq (env "CONFIG_prosody_enable_muc_events" ) "true" ]]muc_events,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_flip_enabled") "true" ]]muc_flip,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_permissions_vpaas_enabled") "true" ]]muc_permissions_vpaas,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_auth_vpaas_enabled") "true" ]]muc_auth_vpaas,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_moderator_enabled") "true" ]]muc_moderators,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_ban_auth_enabled") "true" ]]muc_auth_ban,[[ end -]]
[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" ]]muc_webhooks,[[ end -]]
[[- if eq (env "CONFIG_prosody_muc_allowners") "true" -]]muc_allowners,[[ end ]]
[[- if eq (env "CONFIG_prosody_enable_wait_for_host") "true" ]]muc_wait_for_host,[[ end ]]
[[- if eq (env "CONFIG_prosody_enable_mod_measure_message_count") "true" ]]measure_message_count,[[ end -]]
muc_hide_all"
XMPP_LOBBY_MUC_MODULES="[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" ]]muc_webhooks[[ end ]]"
XMPP_BREAKOUT_MUC_MODULES="
[[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" ]]muc_webhooks[[ end -]]
[[- if eq (env "CONFIG_prosody_enable_mod_measure_message_count") "true" -]]
  [[- if eq (env "CONFIG_prosody_meet_webhooks_enabled") "true" ]],[[ end -]]
  measure_message_count
[[- end -]]"
XMPP_SPEAKERSTATS_MODULES="[[- if eq (env "CONFIG_prosody_enable_muc_events" ) "true" ]]muc_events[[ end -]]"
XMPP_SERVER=localhost
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}
EOF

        destination = "local/prosody.env"
        env = true
      }

      template {
        data = <<EOH

[[ if (env "CONFIG_sip_jibri_shared_secret") ]]
VirtualHost "sipjibri.[[ env "CONFIG_domain" ]]"
    modules_enabled = {
      "ping";
      "smacks";
    }
    authentication = "jitsi-shared-secret"
    shared_secret = "[[ env "CONFIG_sip_jibri_shared_secret" ]]"

[[- end ]]

[[ if or (eq (or (env "CONFIG_jigasi_vault_enabled") "false") "true") (env "CONFIG_jigasi_shared_secret") -]]
VirtualHost "jigasia.[[ env "CONFIG_domain" ]]"
    modules_enabled = {
      "ping";
      "smacks";
    }
    authentication = "jitsi-shared-secret"
    smacks_max_old_sessions = 2000;
[[- if eq (or (env "CONFIG_jigasi_vault_enabled") "false") "true" ]]
{{- with secret "secret/[[ env "CONFIG_environment" ]]/jigasi/xmpp" }}
    shared_secret = "{{ .Data.data.password }}"
{{- end }}
[[- else ]]
    shared_secret = "[[ env "CONFIG_jigasi_shared_secret" ]]"
[[- end ]]
[[- end ]]

EOH
        destination = "local/config/conf.d/other-domains.cfg.lua"
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_prosody_cpu") "200" ]]
        memory    = [[ or (env "CONFIG_nomad_prosody_memory") "2048" ]]
      }
    }
[[- if eq (or (env "CONFIG_prosody_shard_mitm_enabled") "false") "true" ]]
    task "prosody-mitm" {
      driver = "docker"
      config {
        # force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "mitmproxy/mitmproxy:latest"
        ports = ["prosody-mitm"]
        command = "/usr/local/bin/mitmdump"
        args = [
          "--mode",
          "reverse:tcp://${NOMAD_IP_prosody_client}:${NOMAD_HOST_PORT_prosody_client}@${NOMAD_HOST_PORT_prosody_mitm}",
          "--ssl-insecure",
          "-s",
          "/local/save.py",
          "~all"
        ]
      }
      template {
        data = <<EOF
from mitmproxy.net.http.http1.assemble import assemble_request, assemble_response

f = open('/proc/1/fd/1', 'w')

def response(flow):
    f.write(assemble_request(flow.request).decode('utf-8'))
    f.write(assemble_response(flow.response).decode('utf-8', 'replace'))
EOF
        destination = "local/save.py"
        perms = "755"
      }
    }
[[ end ]]
[[- if eq (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
    task "prosody-jvb" {
      driver = "docker"

      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/prosody:[[ env "CONFIG_prosody_tag" ]]"
        ports = ["prosody-jvb-client","prosody-jvb-http"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom","local/config:/config"]
      }


      env {
        PROSODY_MODE="brewery"
        GC_TYPE = "incremental"
        GC_INC_TH = 400
        GC_INC_SPEED = 250
        GC_INC_STEP_SIZE = 13
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        JICOFO_AUTH_PASSWORD = "[[ env "CONFIG_jicofo_auth_password" ]]"
        JVB_AUTH_PASSWORD = "[[ env "CONFIG_jvb_auth_password" ]]"
        JIGASI_XMPP_PASSWORD = "[[ env "CONFIG_jigasi_xmpp_password" ]]"
        JIBRI_RECORDER_PASSWORD = "[[ env "CONFIG_jibri_recorder_password" ]]"
        JIBRI_RECORDER_USER = "[[ env "CONFIG_jibri_recorder_username" ]]"
        JIBRI_XMPP_PASSWORD = "[[ env "CONFIG_jibri_xmpp_password" ]]"
        JIBRI_XMPP_USER = "[[ env "CONFIG_jibri_xmpp_username" ]]"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.[[ env "CONFIG_domain" ]]"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.[[ env "CONFIG_domain" ]]"
        GLOBAL_CONFIG = "console_ports={ 6582 };\nstatistics = \"internal\";\nstatistics_interval = \"manual\";\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\ndebug_traceback_filename = \"traceback.txt\";\nc2s_stanza_size_limit = 10*1024*1024;\n"
        GLOBAL_MODULES = "admin_telnet,http_openmetrics,log_ringbuffer[[ if eq (env "CONFIG_prosody_mod_measure_stanza_counts") "true"]],measure_stanza_counts[[ end ]]"
        PROSODY_LOG_CONFIG="{level = \"debug\", to = \"ringbuffer\",size = [[ or (env "CONFIG_prosody_jvb_mod_log_ringbuffer_size") "1024*1024*4" ]], filename_template = \"traceback.txt\", event = \"debug_traceback/triggered\";};"
        TZ = "UTC"
      }

      template {
        data = <<EOF
# Internal XMPP server
XMPP_SERVER=localhost
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_jvb_client" }}
PROSODY_HTTP_PORT={{ env "NOMAD_HOST_PORT_prosody_jvb_http" }}

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_jvb_http" }}:{{ env "NOMAD_HOST_PORT_prosody_jvb_http" }}
EOF

        destination = "local/prosody-jvb.env"
        env = true
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_prosody_jvb_cpu") "200" ]]
        memory    = [[ or (env "CONFIG_nomad_prosody_jvb_memory") "512" ]]
      }
    }
[[- end ]]
    task "jicofo" {
      driver = "docker"

      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/jicofo:[[ env "CONFIG_jicofo_tag" ]]"
        ports = ["jicofo-http"]
        volumes = [
          "local/config:/config",
          "local/jicofo-service-run:/etc/services.d/jicofo/run",
          "local/11-jicofo-rtcstats-push:/etc/cont-init.d/11-jicofo-rtcstats-push",
          "local/jicofo-rtcstats-push-service-run:/etc/services.d/60-jicofo-rtcstats-push/run"
        ]
      }

      env {
[[ template "common-env" . ]]
        ENABLE_VISITORS = "[[ env "CONFIG_visitors_enabled" ]]"
[[ $SIP_BREWERY_MUC := print "SipBrewery@internal.auth." (env "CONFIG_domain") -]]
        JIBRI_SIP_BREWERY_MUC="[[ or (env "CONFIG_jicofo_sipjibri_brewery_muc") $SIP_BREWERY_MUC ]]"
        JICOFO_ENABLE_REST="1"
        JICOFO_ENABLE_BRIDGE_HEALTH_CHECKS="1"
        JICOFO_HEALTH_CHECKS_USE_PRESENCE="[[ or (env "CONFIG_jicofo_use_presence_for_jvb_health") "false" ]]"
        ENABLE_AUTO_OWNER="[[ if eq (or (env "CONFIG_jicofo_disable_auto_owner") "false") "true" ]]false[[ else ]]true[[ end ]]"
        ENABLE_MODERATOR_CHECKS="[[ if eq (or (env "CONFIG_jicofo_disable_moderator_checks") "false") "true" ]]false[[ else ]]true[[ end ]]"
        OCTO_BRIDGE_SELECTION_STRATEGY="RegionBasedBridgeSelectionStrategy"
        // BRIDGE_STRESS_THRESHOLD=""
        BRIDGE_AVG_PARTICIPANT_STRESS="0.005"
        BRIDGE_STRESS_THRESHOLD="[[ or (env "CONFIG_jicofo_stress_threshold") "0.8" ]]"
        MAX_BRIDGE_PARTICIPANTS="[[ or (env "CONFIG_jicofo_max_bridge_participants") "80" ]]"
        ENABLE_CODEC_AV1="[[ or (env "CONFIG_jicofo_enable_av1") "true" ]]"
        ENABLE_CODEC_VP8="[[ or (env "CONFIG_jicofo_enable_vp8") "true" ]]"
        ENABLE_CODEC_VP9="[[ or (env "CONFIG_jicofo_enable_vp9") "true" ]]"
        ENABLE_CODEC_H264="[[ or (env "CONFIG_jicofo_enable_h264") "true" ]]"
        ENABLE_CODEC_OPUS_RED="[[ env "CONFIG_jicofo_enable_opus_red" ]]"
        ENABLE_OCTO_SCTP="[[ env "CONFIG_jicofo_enable_sctp_relay" ]]"
        JICOFO_TRUSTED_DOMAINS="auth.[[ env "CONFIG_domain" ]],recorder.[[ env "CONFIG_domain" ]],jigasia.[[ env "CONFIG_domain" ]],jigasib.[[ env "CONFIG_domain" ]]"
        JICOFO_CONF_SSRC_REWRITING="[[ env "CONFIG_jicofo_ssrc_rewriting" ]]"
        JICOFO_CONF_MAX_AUDIO_SENDERS="[[ env "CONFIG_jicofo_max_audio_senders" ]]"
        JICOFO_CONF_MAX_VIDEO_SENDERS="[[ env "CONFIG_jicofo_max_video_senders" ]]"
        JICOFO_CONF_STRIP_SIMULCAST="[[ env "CONFIG_jicofo_strip_simulcast" ]]"
        JICOFO_MULTI_STREAM_BACKWARD_COMPAT="1"
        JICOFO_CONF_SOURCE_SIGNALING_DELAYS="[[ or (env "CONFIG_jicofo_source_signaling_delay") "{ 50: 1000, 100: 2000 }" ]]"
        JIBRI_PENDING_TIMEOUT="[[ or (env "CONFIG_jicofo_jibri_pending_timeout") "90" ]] seconds"
        JICOFO_MAX_MEMORY="1536m"
        JICOFO_BRIDGE_REGION_GROUPS = "[\"eu-central-1\", \"eu-west-1\", \"eu-west-2\", \"eu-west-3\", \"uk-london-1\", \"eu-amsterdam-1\", \"eu-frankfurt-1\"],[\"us-east-1\", \"us-west-2\", \"us-ashburn-1\", \"us-phoenix-1\"],[\"ap-mumbai-1\", \"ap-tokyo-1\", \"ap-south-1\", \"ap-northeast-1\"],[\"ap-sydney-1\", \"ap-southeast-2\"],[\"ca-toronto-1\", \"ca-central-1\"],[\"me-jeddah-1\", \"me-south-1\"],[\"sa-saopaulo-1\", \"sa-east-1\"]"
        JICOFO_ENABLE_HEALTH_CHECKS="1"
        # jicofo rtcstats push vars
        JICOFO_ADDRESS = "http://127.0.0.1:8888"
        JICOFO_VISITORS_REQUIRE_MUC_CONFIG = "[[ env "CONFIG_jicofo_require_muc_config_flag" ]]"
        RTCSTATS_SERVER="[[ env "CONFIG_jicofo_rtcstats_push_rtcstats_server" ]]"
        INTERVAL=10000
        JICOFO_LOG_FILE = "/local/jicofo.log"
        VISITORS_XMPP_AUTH_DOMAIN="auth.[[ env "CONFIG_domain" ]]"
      }

      artifact {
        source      = "https://github.com/jitsi/jicofo-rtcstats-push/releases/download/release-0.0.1/jicofo-rtcstats-push.zip"
        mode = "file"
        destination = "local/jicofo-rtcstats-push.zip"
        options {
          archive = false
        }
      }
      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

JAVA_SYS_PROPS="-Djava.util.logging.config.file=/config/logging.properties -Dconfig.file=/config/jicofo.conf"
DAEMON=/usr/share/jicofo/jicofo.sh
DAEMON_DIR=/usr/share/jicofo/

JICOFO_CMD="exec $DAEMON"

[ -n "$JICOFO_LOG_FILE" ] && JICOFO_CMD="$JICOFO_CMD 2>&1 | tee $JICOFO_LOG_FILE"

exec s6-setuidgid jicofo /bin/bash -c "cd $DAEMON_DIR; JAVA_SYS_PROPS=\"$JAVA_SYS_PROPS\" $JICOFO_CMD"
EOF
        destination = "local/jicofo-service-run"
        perms = "755"
      }


      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

apt-get update && apt-get -y install unzip cron

mkdir -p /jicofo-rtcstats-push
cd /jicofo-rtcstats-push
unzip /local/jicofo-rtcstats-push.zip

echo '0 * * * * /local/jicofo-log-truncate.sh' | crontab 

EOF
        destination = "local/11-jicofo-rtcstats-push"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

echo > $JICOFO_LOG_FILE
EOF
        destination = "local/jicofo-log-truncate.sh"
        perms = "755"
      }

      template {
        data = <<EOF
#!/usr/bin/with-contenv bash

exec node /jicofo-rtcstats-push/app.js

EOF
        destination = "local/jicofo-rtcstats-push-service-run"
        perms = "755"

      }

      template {
        data = <<EOF
VISITORS_XMPP_SERVER=[[ range $index, $i := split " "  (seq 0 ((sub $VNODE_COUNT 1)|int)) ]][[ if gt ($i|int) 0 ]],[[ end ]]localhost:[[ add $VNODE_CLIENT_PORT ($i|int) ]][[ end ]]  
#
# Basic configuration options
#
[[ if ne (or (env "CONFIG_jicofo_visitors_max_participants") "false") "false" -]]
VISITORS_MAX_PARTICIPANTS="[[ env "CONFIG_jicofo_visitors_max_participants" ]]"
[[ end -]]
[[ if ne (or (env "CONFIG_jicofo_visitors_max_visitors_per_node") "false") "false" -]]
VISITORS_MAX_VISITORS_PER_NODE="[[ env "CONFIG_jicofo_visitors_max_visitors_per_node" ]]"
[[ end -]]

[[- if eq (or (env "CONFIG_prosody_shard_mitm_enabled") "false") "true" ]]
JICOFO_OPTS="-Djicofo.xmpp.client.port={{ env "NOMAD_HOST_PORT_prosody_mitm" }}"
[[ else ]]
JICOFO_OPTS="-Djicofo.xmpp.client.port={{ env "NOMAD_HOST_PORT_prosody_client" }}"
[[ end ]]

# Exposed HTTP port
HTTP_PORT={{ env "NOMAD_HOST_PORT_http" }}

# Exposed HTTPS port
HTTPS_PORT={{ env "NOMAD_HOST_PORT_https" }}

# Internal XMPP server
XMPP_SERVER=localhost
[[- if eq (or (env "CONFIG_prosody_shard_mitm_enabled") "false") "true" ]]
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_mitm" }}
[[ else ]]
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_client" }}
[[ end ]]

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_http" }}:{{ env "NOMAD_HOST_PORT_prosody_http" }}

[[- if eq (or (env "CONFIG_prosody_brewery_shard_enabled") "true") "true" ]]
JVB_XMPP_SERVER=localhost
JVB_XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_jvb_client" }}
[[- else ]]
JVB_XMPP_SERVER=localhost
JVB_XMPP_PORT=6222
JVB_BREWERY_MUC="release-[[ env "CONFIG_release_number" ]]"
[[- end ]]

EOF

        destination = "local/jicofo.env"
        env = true
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_jicofo_cpu") "200" ]]
        memory    = [[ or (env "CONFIG_nomad_jicofo_memory") "3072" ]]
      }
    }

    task "web-nginx-prometheus-exporter" {
      driver = "docker"
      config {
        image        = "nginx/nginx-prometheus-exporter:1.3.0"
        ports = ["web-nginx-prometheus-exporter"]
      }

      env {
        SCRAPE_URI="http://localhost:888/nginx_status"
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_web_nginx_prometheus_exporter_cpu") "100" ]]
        memory    = [[ or (env "CONFIG_nomad_web_nginx_prometheus_exporter_memory") "512" ]]
      }
    }

    task "web" {
      # wait until everything else is started before nginx
      lifecycle {
        hook = "poststart"
        sidecar = true
      }

      driver = "docker"
      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "nginx:1.25.3"
        ports = ["http","nginx-status"]
        volumes = [
          "local/_unlock:/usr/share/nginx/html/_unlock",
          "local/_unlock:/usr/share/nginx/html/_health",
          "local/nginx.conf:/etc/nginx/nginx.conf",
          "local/conf.d:/etc/nginx/conf.d",
          "local/conf.stream:/etc/nginx/conf.stream",
          "local/consul-resolved.conf:/etc/systemd/resolved.conf.d/consul.conf"
        ]
      }
      env {
        NGINX_WORKER_PROCESSES = 4
        NGINX_WORKER_CONNECTIONS = 1024
      }
      template {
        destination = "local/nginx.conf"

  data = <<EOF
[[ template "nginx.conf" . ]]
EOF
    }

      # template file for nginx status server
      template {
        data = <<EOF
[[ template "nginx-status.conf" . ]]
EOF
        destination = "local/conf.d/nginx-status.conf"
      }

      # template file for nginx stream configuration
      template {
        data = <<EOF
[[ template "nginx-streams.conf" . ]]
EOF
        destination = "local/conf.stream/nginx-streams.conf"
[[ template "nginx-reload" . ]]
      }

      # template file for main nginx site configuration
      template {
        data = <<EOF
[[ template "nginx-site.conf" . ]]
EOF
        destination = "local/conf.d/default.conf"
[[ template "nginx-reload" . ]]
      }

      # template file for _unlock contents
      template {
        destination = "local/_unlock"
  data = <<EOF
OK
EOF
      }

      # use consul DNS for name resolution in nginx container
      template {
        destination = "local/consul-resolved.conf"
        data = <<EOF
[Resolve]
DNS={{ env "attr.unique.network.ip-address" }}:8600
DNSSEC=false
Domains=~consul
EOF
      }
      resources {
        cpu    = [[ or (env "CONFIG_nomad_web_cpu") "200" ]]
        memory    = [[ or (env "CONFIG_nomad_web_memory") "512" ]]
      }
    }
  }
}
