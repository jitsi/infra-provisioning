variable "dc" {
  type = list(string)
}

job "fabio" {
  datacenters = var.dc
  type = "system"

  group "fabio" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    network {
      port "ext-lb" {
        static = 9999
      }
      port "ext-ui" {
        static = 9998
      }
      port "ext-metrics" {}
      port "int-lb" {
        static = 9997
      }
      port "int-ui" {
        static = 9996
      }
      port "int-metrics" {}
    }

    service {
      name = "fabio-ext"
      tags = [
        "ip-${attr.unique.network.ip-address}"
      ]
      meta {
        metrics_port = "${NOMAD_PORT_ext_metrics}"
      }
    }

    service {
      name = "fabio-int"
      tags = [
        "ip-${attr.unique.network.ip-address}"
      ]
      meta {
        metrics_port = "${NOMAD_PORT_int_metrics}"
      }
    }

    task "ext-fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
        ports = ["ext-lb","ext-ui","ext-metrics"]
      }

      env {
        #FABIO_log_access_format = "combined"
        FABIO_log_access_format = "[$time_common] $remote_host - \"$request\" $response_status $response_body_size - $upstream_service: $upstream_addr$upstream_request_uri - Referer: $header.Referer X-Forwarded-For: $header.x-forwarded-for X-Forwarded-Host $header.x-forwarded-host - $header.User-Agent"
        FABIO_log_access_target = "stdout"
        FABIO_metrics_prometheus_subsystem = "fabio_ext"
        FABIO_metrics_target = "prometheus"
        FABIO_proxy_addr = ":9999,:${NOMAD_PORT_ext-metrics};proto=prometheus"
        FABIO_ui_addr = ":9998"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }

    task "int-fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
        ports = ["int-lb","int-ui","int-metrics"]
      }

      env {
        #FABIO_log_access_format = "combined"
        FABIO_log_access_format = "[$time_common] $remote_host - \"$request\" $response_status $response_body_size - $upstream_service: $upstream_addr$upstream_request_uri - Referer: $header.Referer X-Forwarded-For: $header.x-forwarded-for X-Forwarded-Host $header.x-forwarded-host - $header.User-Agent"
        FABIO_log_access_target = "stdout"
        FABIO_metrics_prometheus_subsystem = "fabio_int"
        FABIO_metrics_target = "prometheus"
        FABIO_proxy_addr = ":9997,:${NOMAD_PORT_int-metrics};proto=prometheus"
        FABIO_registry_consul_tagprefix = "int-urlprefix-"
        FABIO_ui_addr = ":9996"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}
