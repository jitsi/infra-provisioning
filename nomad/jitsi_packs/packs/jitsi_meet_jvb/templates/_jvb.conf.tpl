[[ define "jvb-config" -]]
# This is the new config file for jitsi-videobridge. For possible options and
# default values see the reference.conf file in the jvb repo:
# https://github.com/jitsi/jitsi-videobridge/blob/master/src/main/resources/reference.conf
#
# Since the defaults are already provided in reference.conf we should keep this
# file as thin as possible.
videobridge {

  initial-drain-mode = [[ or (env "CONFIG_jvb_initial_drain_mode") "false" ]]

  redact-remote-addresses = [[ or (env "CONFIG_jvb_redact_remote_addresses") "true" ]]

  load-management {
    average-participant-stress = [[ or (env "CONFIG_jvb_average_participant_stress") "0.005" ]]

    load-measurements {
      [[ if eq (or (env "CONFIG_jvb_use_cpu_for_stress") "true") "true" ]]
      load-measurement = "cpu-usage"
      [[ end ]]
      packet-rate {
        # The packet rate at which we'll consider the bridge overloaded
        load-threshold = [[ or (env "CONFIG_jvb_load_threshold") "85000" ]]

        # The packet rate at which we'll consider the bridge 'underloaded' enough
        # to start recovery
        recovery-threshold = [[ or (env "CONFIG_recovery_threshold") "68000" ]]
      }
      cpu-usage {
        load-threshold = [[ or (env "CONFIG_jvb_load_threshold_cpu") "0.9" ]]
        recovery-threshold = [[ or (env "CONFIG_jvb_recovery_threshold_cpu") "0.72" ]]
      }
    }
  }

  cc {
    [[ if eq (or (env "CONFIG_jvb_disable_bwe") "false") "true" ]]
    trust-bwe = false
    [[ end ]]

    [[ if ne (or (env "CONFIG_jvb_last_n_limits") "25") "false" ]]
    jvb-last-n = [[ or (env "CONFIG_jvb_last_n_limits") "25" ]]
    [[ end ]]

    [[ if ne (or (env "CONFIG_jvb_assumed_bandwidth_limit") "10 Mbps") "false" ]]
    assumed-bandwidth-limit = [[ or (env "CONFIG_jvb_assumed_bandwidth_limit") "10 Mbps" ]]
    [[ end ]]

    [[ if ne (or (env "CONFIG_jvb_use_vla_target_bitrate") "false") "false" ]]
    use-vla-target-bitrate =  [[ or (env "CONFIG_jvb_use_vla_target_bitrate") "false" ]]
    [[ end ]]
  }
  cryptex {
    [[ if eq (or (env "CONFIG_jvb_enable_cryptex_endpoint") "false") "true" ]]
    endpoint = true
    [[ end ]]

    [[ if eq (or (env "CONFIG_jvb_enable_cryptex_relay") "true") "true" ]]
    relay = true
    [[ end ]]
  }

  health {
    sticky-failures = true
    require-stun = [[ or (env "CONFIG_jvb_require_stun") "true" ]]
  }

  ice {
    tcp {
      [[ if eq (or (env "CONFIG_jvb_disable_tcp") "true") "true" ]]
      enabled = false
      [[ end ]]
    }
    
    udp {
      port = [{ env "NOMAD_HOST_PORT_media" }]
    }

[[ if eq (or (env "CONFIG_jvb_enable_ufrag_prefix") "false") "true" ]]
    ufrag-prefix="[{ env "NOMAD_SHORT_ALLOC_ID" }]"
[[ end ]]

[[ if ne (or (env "CONFIG_jvb_nomination_strategy") "NominateFirstHostOrReflexiveValid") "false" ]]
    nomination-strategy="[[ or (env "CONFIG_jvb_nomination_strategy") "NominateFirstHostOrReflexiveValid" ]]"
[[ end ]]


[[ if eq (or (env "CONFIG_jvb_suppress_private_candidates") "true") "true" ]]
   advertise-private-candidates=false
[[ end ]]
  }

  apis {
    rest {
      enabled=true
    }
    xmpp-client {
[[ if eq (or (env "CONFIG_jvb_enable_stats_filter") "true") "true" ]]
      stats-filter {
        enabled = true
      }
[[ end ]]
    }
  }

  stats {
    enabled = true
    transit-time {
      enable-json = false
      enable-prometheus = true
    }
  }

  websockets {
[[ if eq (or (env "CONFIG_jvb_enable_websockets") "true") "true" ]]
    enabled = true
    tls = true
    domain = "[[ env "CONFIG_domain" ]]:443"
    // Set both 'domain' and 'domains' for backward compat with jvb versions that don't support "domains".
    [[ if eq (or (env "CONFIG_jvb_ws_additional_domain_enabled") "false") "true" ]]
    domains = [
        "[[ env "CONFIG_jvb_ws_additional_domain" ]]:443"
    ]
    [[ end ]]
    server-id = "jvb-[{ env "NOMAD_ALLOC_ID" }]"

    [[ if ne (or (env "CONFIG_jvb_ws_relay_domain") "false") "false" ]]
    relay-domain = "[[ env "CONFIG_jvb_ws_relay_domain" ]]:443"
    [[ end ]]
[[ else ]]
    enabled = false
[[ end ]]
  }

  http-servers {
    private {
        host = 0.0.0.0
        send-server-version = false
    }
    public {
[[ if eq (or (env "CONFIG_jvb_enable_websockets") "true") "true" ]]
      host = 0.0.0.0
      port=9090
[[ if eq (or (env "CONFIG_jvb_enable_websockets_ssl") "false") "true" ]]
      tls-port=9091
      key-store-path=/config/ssl.store
      key-store-password=[[ or (env "CONFIG_jvb_websockets_ssl_keystore_password") "replaceme" ]]
[[ end ]]
[[ end ]]
    }
  }

  rest {
    shutdown {
      enabled = true
    }
  }

  relay {
[[ if eq (or (env "CONFIG_jvb_enable_octo") "true") "true" ]]
    enabled = true
    region = [[ env "CONFIG_octo_region" ]]
    relay-id = "[{ env "NOMAD_ALLOC_ID" }]"
[[ else ]]
    enabled = false
[[ end ]]
  }

  sctp {
    enabled = [[ or (env "CONFIG_jvb_enable_sctp") "true" ]]
[[ if eq (or (env "CONFIG_jvb_use_dcsctp") "true") "true" ]]
    use-usrsctp = false
[[ end ]]
  }

  shutdown {
    graceful-shutdown-max-duration = [[ or (env "CONFIG_jvb_graceful_shutdown_max_duration") "1 hour" ]]
    graceful-shutdown-min-participants = [[ or (env "CONFIG_jvb_graceful_shutdown_min_participants") "0" ]]
  }

  version {
    announce = [[ or (env "CONFIG_jvb_announce_version") "true" ]]
    release = [[ env "CONFIG_release_number" ]]
  }

  speech-activity {
    recent-speakers-count = [[ or (env "CONFIG_jvb_recent_speakers_count") "30" ]]
    enable-silence-detection = [[ or (env "CONFIG_jvb_enable_silence_detection") "false" ]]
  }

  loudest {
    route-loudest-only = [[ or (env "CONFIG_jvb_route_loudest_only") "true" ]]
  }

  ssrc-limit {
    video = [[ or (env "CONFIG_jvb_ssrc_limit_video") "50" ]]
    audio = [[ or (env "CONFIG_jvb_ssrc_limit_audio") "50" ]]
  }
}

jmt {
  audio {
    red {
      policy = [[ or (env "CONFIG_jvb_red_policy") "NOOP" ]]
      distance = [[ or (env "CONFIG_jvb_red_distance") "TWO" ]]
      vad-only = [[ or (env "CONFIG_jvb_red_vad_only") "true" ]]
    }
  }
[[ if eq (or (env "CONFIG_jvb_enable_pcap") "false") "true" ]]
  debug {
    pcap {
      enabled = true
      directory = "/local"
    }
  }
[[ end ]]
  bwe {
    send-side {
      loss-experiment {
        probability = [[ or (env "CONFIG_jvb_loss_experiment_probability") "0" ]]
        bitrate-threshold = [[ or (env "CONFIG_jvb_loss_bitrate_threshold_kbps") "1000" ]] kbps
      }
    }
[[ if ne (or (env "CONFIG_jvb_use_google_cc2_bwe") "true") "false" ]]
   estimator {
       engine = GoogleCc2
    }
[[ end ]]
  }
[[ if eq (or (env "CONFIG_jvb_skip_authentication_for_silence") "false") "true" ]]
  srtp {
    # Optimisation: do not authenticate silence except once every 1000 packets.
    max-consecutive-packets-discarded-early = 1000
  }
[[ end ]]
}

{{/* assign env from context, preserve during range when . is re-assigned */}}
{{ $ENV := .Env -}}
{{ $JVB_ADVERTISE_IPS := .Env.JVB_ADVERTISE_IPS | default "" -}}
{{ $JVB_IPS := splitList "," $JVB_ADVERTISE_IPS -}}
{{ $JVB_NAT_PORT := .Env.JVB_NAT_PORT | default .Env.JVB_PORT -}}

ice4j {
  harvest {
    udp.receive-buffer-size = [[ or (env "CONFIG_jvb_udp_buffer_size") "104857600" ]]
    mapping {
        aws.enabled = false
[[ if eq (or (env "CONFIG_jvb_stun_mapping_enabled") "true") "true" ]]
        stun.addresses = [ "meet-jit-si-turnrelay.jitsi.net:443" ]
[[ else ]]
        stun.enabled = false
[[ end ]]
            static-mappings = [
{{ range $index, $element := $JVB_IPS }}
{{ if ne $index 0 }},{{ end }}
                {
                    local-address = "{{ $ENV.LOCAL_ADDRESS }}"
                    local-port = [{ env "NOMAD_HOST_PORT_media" }]
                    public-address = "{{ $element }}"
                    public-port = "{{ $JVB_NAT_PORT }}"
                    name = "ip-{{ $index }}"
                }
{{ end }}
            ]
    }
  }
}

include "xmpp.conf"
[[ end -]]

[[ define "xmpp-config" ]]
[[ template "shard-lookup" . ]]
[[ $shard_brewery_enabled := or (env "CONFIG_jvb_shard_brewery_enabled") "true" ]]
videobridge.apis.xmpp-client.configs {
{{ range $sindex, $item := scratch.MapValues "shards" -}}
    # SHARD {{ .ServiceMeta.shard }}
    {{ .ServiceMeta.shard }} {
        HOSTNAME={{ .Address }}
        PORT={{ with .ServiceMeta.prosody_jvb_client_port}}{{.}}{{ else }}6222{{ end }}
        DOMAIN=auth.jvb.{{ .ServiceMeta.domain }}
[[ if eq $shard_brewery_enabled "false" -]]
        MUC_JIDS="release-[[ or (env "CONFIG_release_number") "0" ]]@muc.jvb.{{ .ServiceMeta.domain }}"
[[- else ]]
        MUC_JIDS="jvbbrewery@muc.jvb.{{ .ServiceMeta.domain }}"
[[- end ]]
        USERNAME=[[ or (env "CONFIG_jvb_auth_username") "jvb" ]]
        PASSWORD=[[ env "CONFIG_jvb_auth_password" ]]
        MUC_NICKNAME=jvb-{{ env "NOMAD_ALLOC_ID" }}
        IQ_HANDLER_MODE=[[ or (env "CONFIG_jvb_iq_handler_mode") "sync" ]]
        # TODO: don't disable :(
        DISABLE_CERTIFICATE_VERIFICATION=true
    }
{{ end -}}
}
[[ end -]]

[[ define "logging-properties" ]]
handlers= java.util.logging.ConsoleHandler

java.util.logging.ConsoleHandler.level = ALL
java.util.logging.ConsoleHandler.formatter = org.jitsi.utils.logging2.JitsiLogFormatter

org.jitsi.utils.logging2.JitsiLogFormatter.programname=JVB

.level=INFO

[[- if eq (env "CONFIG_jvb_enable_sctp_debug_logs") "true" ]]
org.jitsi.videobridge.sctp.level=ALL
[[- end ]]

# This is intentionally always enabled, it's not noisy and includes
# logging assert failures from usrsctp
org.jitsi_modified.sctp4j.SctpJni.level=ALL

[[- if eq (env "CONFIG_jvb_enable_message_transport_logs") "true" ]]
org.jitsi.videobridge.EndpointMessageTransport.level=ALL
org.jitsi.videobridge.relay.RelayMessageTransport.level=ALL
[[- end ]]

[[- if eq (env "CONFIG_jvb_enable_route_loudest_logs") "true" ]]
org.jitsi.utils.dsi.DominantSpeakerIdentification.level=ALL
[[- end ]]

# We need this for SENT and RECV messages (for COLIBRI signaling) now.
org.jitsi.videobridge.xmpp.XmppConnection.level=ALL

# time series logging
java.util.logging.SimpleFormatter.format= %5$s%n
java.util.logging.FileHandler.level = ALL
java.util.logging.FileHandler.formatter = java.util.logging.SimpleFormatter
java.util.logging.FileHandler.pattern = [[ or (env "CONFIG_jvb_log_series_path") "/tmp/jvb-series.log" ]]
java.util.logging.FileHandler.limit = [[ or (env "CONFIG_jvb_log_series_file_size_limit") "20000000" ]]
java.util.logging.FileHandler.count = 1
java.util.logging.FileHandler.append = false

[[- if eq (env "CONFIG_jvb_enable_all_timeseries") "true" ]]
timeseries.level=ALL
[[- else ]]
timeseries.level=OFF
[[- end ]]
[[- if eq (env "CONFIG_jvb_enable_bwe_timeseries") "true" ]]
timeseries.org.jitsi.nlj.rtp.bandwidthestimation.level=ALL
timeseries.org.jitsi.nlj.rtp.bandwidthestimation2.level=ALL
[[- end ]]
[[- if eq (env "CONFIG_jvb_enable_brctrl_timeseries") "true" ]]
timeseries.org.jitsi.videobridge.cc.BitrateController.level=ALL
[[- end ]]
timeseries.useParentHandlers = false
timeseries.handlers = java.util.logging.FileHandler

[[ end -]]
