variable "dc" {
  type = string
}
variable "grid" {
  type = string
}

variable "max_sessions" {
  type = number
  default = 1
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "system"

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "node" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "selenium-grid"
    }
    constraint {
      attribute  = "${meta.selenium_grid_name}"
      value     = "${var.grid}"
    }

    count = 1

    network {
      port "http" {
      }
      port "vnc" {
      }
      port "no-vnc" {
      }
    }

    service {
      name = "grid-node"
      tags = ["grid-${var.grid}"]
      port = "http"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "node" {
      driver = "docker"

      config {
        image        = "selenium/node-chrome:4.26"
        ports = ["http","vnc","no-vnc"]
        volumes = [
          "/opt/jitsi/jitsi-meet-torture:/usr/share/jitsi-meet-torture:ro",
        ]

        # 2gb shm
        shm_size = 2147483648
      }

      template {
        data = <<EOF
{{ range service "grid-${var.grid}.grid-hub" -}}
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc" }}"
SE_ENABLE_TRACING="false"
#SE_OPTS="--log-level FINE"
        EOF
        destination = "local/selenium.env"
        env = true
      }
      resources {
        cpu    = 4000
        memory = 6144
      }
    }
  }
}
