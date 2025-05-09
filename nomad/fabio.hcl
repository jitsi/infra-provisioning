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
      port "ext-metrics" {
      }
      port "int-lb" {
        static = 9997
      }
      port "int-ui" {
        static = 9996
      }
      port "int-metrics" {
      }
    }
    service "fabio-ext" {
      name = "fabio-ext"
      port = "ext-lb"

    }
    task "ext-fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
        ports = ["ext-lb","ext-ui","ext-metrics"]
      }

      env {
        FABIO_metrics_prometheus_subsystem = "fabio_ext"
        FABIO_proxy_addr = ":9999,:${NOMAD_PORT_ext_metrics};proto=prometheus"
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
        FABIO_registry_consul_tagprefix = "int-urlprefix-"
        FABIO_metrics_prometheus_subsystem = "fabio_int"
        FABIO_proxy_addr = ":9997,:${NOMAD_PORT_int_metrics};proto=prometheus"
        FABIO_ui_addr = ":9996"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }
  }
}
