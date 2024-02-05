job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [ "[[ var "datacenter" . ]]" ]
  type = "service"

  meta {
    domain = "[[ env "CONFIG_domain" ]]"
    environment = "[[ env "CONFIG_environment" ]]"
    octo_region = "[[ env "CONFIG_octo_region" ]]"
    cloud_provider = "[[ env "CONFIG_cloud_provider" ]]"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "brewery" {
    count = 1

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "[[ env "CONFIG_pool_type" ]]"
    }


    network {
      port "prosody-brewery-client" {
      }
      port "prosody-brewery-http" {
        to = 5280
      }
    }

    service {
      name = "prosody-brewery-http"
      tags = ["ip-${attr.unique.network.ip-address}"]
      port = "prosody-brewery-http"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        environment = "${meta.environment}"
      }
      check {
        name     = "health"
        type     = "http"
        path     = "/metrics"
        port     = "prosody-brewery-http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {

      name = "prosody-brewery"
      meta {
        domain = "[[ env "CONFIG_domain" ]]"
        environment = "${meta.environment}"
        shard = "prosody-brewery-[[ env "CONFIG_octo_region"]]"
        prosody_jvb_client_port = "${NOMAD_HOST_PORT_prosody_brewery_client}"
      }

      port = "prosody-brewery-client"

    }

    task "brewery" {
      driver = "docker"

      config {
        force_pull = [[ or (env "CONFIG_force_pull") "false" ]]
        image        = "jitsi/prosody:[[ env "CONFIG_prosody_tag" ]]"
        ports = ["prosody-brewery-client","prosody-brewery-http"]
        volumes = ["local/prosody-plugins-custom:/prosody-plugins-custom","local/config:/config"]
      }


      env {
        PROSODY_MODE="brewery"
        LOG_LEVEL = "[[ or (env "CONFIG_prosody_log_level") "debug" ]]"
        XMPP_DOMAIN = "[[ env "CONFIG_domain" ]]"
        PUBLIC_URL="https://[[ env "CONFIG_domain" ]]/"
        JICOFO_AUTH_PASSWORD = "[[ env "CONFIG_jicofo_auth_password" ]]"
        JVB_AUTH_PASSWORD = "[[ env "CONFIG_jvb_auth_password" ]]"
        JIGASI_XMPP_PASSWORD = "[[ env "CONFIG_jigasi_xmpp_password" ]]"
        JIBRI_RECORDER_PASSWORD = "[[ env "CONFIG_jibri_recorder_password" ]]"
        JIBRI_XMPP_PASSWORD = "[[ env "CONFIG_jibri_xmpp_password" ]]"
        JVB_XMPP_AUTH_DOMAIN = "auth.jvb.[[ env "CONFIG_domain" ]]"
        JVB_XMPP_INTERNAL_MUC_DOMAIN = "muc.jvb.[[ env "CONFIG_domain" ]]"
        # match any muc in the brewery muc component as per https://modules.prosody.im/mod_firewall
        JVB_BREWERY_MUC="<*>"
        GLOBAL_CONFIG = "statistics = \"internal\";\nstatistics_interval = \"manual\";\nopenmetrics_allow_cidr = \"0.0.0.0/0\";\ndebug_traceback_filename = \"traceback.txt\";\nc2s_stanza_size_limit = 10*1024*1024;\n"
        GLOBAL_MODULES = "admin_telnet,http_openmetrics,log_ringbuffer[[ if eq (env "CONFIG_prosody_mod_measure_stanza_counts") "true" ]],measure_stanza_counts[[ end ]]"
        PROSODY_LOG_CONFIG="{level = \"debug\", to = \"ringbuffer\",size = [[ or (env "CONFIG_prosody_jvb_mod_log_ringbuffer_size") "1024*1024*4" ]], filename_template = \"traceback.txt\", event = \"debug_traceback/triggered\";};"
        TZ = "UTC"
      }

      template {
        data = <<EOF
# Internal XMPP server
XMPP_SERVER={{ env "NOMAD_IP_prosody_brewery_client" }}
XMPP_PORT={{  env "NOMAD_HOST_PORT_prosody_brewery_client" }}

# Internal XMPP server URL
XMPP_BOSH_URL_BASE=http://{{ env "NOMAD_IP_prosody_brewery_http" }}:{{ env "NOMAD_HOST_PORT_prosody_brewery_http" }}
EOF

        destination = "local/prosody-brewery.env"
        env = true
      }

      resources {
        cpu    = [[ or (env "CONFIG_nomad_prosody_brewery_cpu") "1024" ]]
        memory    = [[ or (env "CONFIG_nomad_prosody_brewery_memory") "512" ]]
      }
    }
  }
}
