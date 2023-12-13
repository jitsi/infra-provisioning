[[ define "jvb-config" -]]
# This is the new config file for jitsi-videobridge. For possible options and
# default values see the reference.conf file in the jvb repo:
# https://github.com/jitsi/jitsi-videobridge/blob/master/src/main/resources/reference.conf
#
# Since the defaults are already provided in reference.conf we should keep this
# file as thin as possible.
videobridge {

  initial-drain-mode = [[ or (env "CONFIG_jvb_initial_drain_mode") "false" ]]

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
  }
  cryptex {
    [[ if eq (or (env "CONFIG_jvb_enable_cryptex_endpoint") "false") "true" ]]
    endpoint = true
    [[ end ]]

    [[ if eq (or (env "CONFIG_jvb_enable_cryptex_relay") "false") "true" ]]
    relay = true
    [[ end ]]
  }

  health {
    sticky-failures = true
  }

  ice {
    tcp {
      [[ if eq (or (env "CONFIG_jvb_disable_tcp") "true") "true" ]]
      enabled = false
      [[ end ]]
    }
    
    udp {
      port = {{ env "NOMAD_HOST_PORT_media" }}
    }

[[ if eq (or (env "CONFIG_jvb_enable_ufrag_prefix") "false") "true" ]]
    ufrag-prefix="{{ env "NOMAD_SHORT_ALLOC_ID" }}"
[[ end ]]

[[ if ne (or (env "CONFIG_jvb_nomination_strategy") "NominateFirstHostOrReflexiveValid") "false" ]]
    nomination-strategy="[[ or (env "CONFIG_jvb_nomination_strategy") "NominateFirstHostOrReflexiveValid" ]]"
[[ end ]]


[[ if eq (or (env "CONFIG_jvb_suppress_private_candidates") "true") "true" ]]
   advertise-private-candidates=false
[[ end ]]
  }

  multi-stream {
    enabled = [[ or (env "CONFIG_jvb_enable_multi_stream") "true" ]]
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
  }

  websockets {
[[ if eq (or (env "CONFIG_jvb_enable_websockets") "true") "true" ]]
    enabled = true
    tls = true
    domain = "[[ env "CONFIG_domain" ]]:443"
    // Set both 'domain' and 'domains' for backward compat with jvb versions that don't support "domains".
    [[ if eq (or (env "CONFIG_jvb_ws_additional_domain_enabled") "true") "true" ]]
    domains = [
        "[[ env "CONFIG_jvb_ws_additional_domain" ]]:443"
    ]
    [[ end ]]
    server-id = "jvb-{{ env "NOMAD_ALLOC_ID" }}"

    [[ if ne (or (env "CONFIG_jvb_ws_relay_domain") "false") "false" ]]
    relay-domain = "[[ env "CONFIG_jvb_ws_relay_domain" ]]:443"
    [[ end ]]
[[ else ]]
    enabled = false
[[ end ]]
  }

  http-servers {
    public {
[[ if eq (or (env "CONFIG_jvb_enable_websockets") "true") "true" ]]
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
    relay-id = "{{ env "NOMAD_ALLOC_ID" }}"
[[ else ]]
    enabled = false
[[ end ]]
  }

  sctp {
    enabled = [[ or (env "CONFIG_jvb_enable_sctp") "false" ]]
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
  }
[[ if eq (or (env "CONFIG_jvb_skip_authentication_for_silence") "false") "true" ]]
  srtp {
    # Optimisation: do not authenticate silence except once every 1000 packets.
    max-consecutive-packets-discarded-early = 1000
  }
[[ end ]]
}

ice4j {
  harvest {
    udp.receive-buffer-size = [[ or (env "CONFIG_jvb_udp_buffer_size") "104857600" ]]
    mapping.aws.enabled = false
[[ if eq (or (env "CONFIG_jvb_stun_mapping_enabled") "true") "true" ]]
    mapping.stun.addresses = [ "meet-jit-si-turnrelay.jitsi.net:443" ]
[[ else ]]
    mapping.stun.enabled = false
[[ end ]]
  }
}

include "xmpp.conf"
[[ end -]]