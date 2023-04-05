variable "dc" {
  type = list(string)
}

job "fabio" {
  datacenters = var.dc
  type = "system"

  group "fabio" {
    network {
      port "ext-lb" {
        static = 9999
      }
      port "ext-ui" {
        static = 9998
      }
      port "int-lb" {
        static = 9997
      }
      port "int-ui" {
        static = 9996
      }
    }
    task "ext-fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
        ports = ["ext-lb","ext-ui"]
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
    task "int-fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
        ports = ["int-lb","int-ui"]
      }

      env {
        FABIO_registry_consul_tagprefix = "int-urlprefix-"
        FABIO_proxy_addr = ":9997"
        FABIO_ui_addr = ":9996"
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
