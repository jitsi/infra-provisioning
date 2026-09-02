variable "dc" {
  type = string
}
variable "grid" {
  type = string
}
variable "registry_prefix" {
  type = string
  default = ""
}

variable "max_sessions" {
  type = number
  default = 1
}

variable "image_version" {
  type = string
  default = "latest"
}

variable "dns_zone" {
  type = string
  default = "jitsi.net"
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

  // The node image is arm64-only (Google now ships Chrome for linux-arm64).
  // Without this, a system job schedules onto x86 pool hosts too and the task
  // dies at container start with "exec format error" -- silently missing slots
  // with a green deploy.
  constraint {
    attribute = "${attr.cpu.arch}"
    value     = "arm64"
  }

  group "grid-node" {
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

    shutdown_delay = "10s"
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

    task "grid-node" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-mixed:${var.image_version}"
        # image_version defaults to "latest", a mutable tag. Without force_pull a
        # restarted allocation keeps the cached layer, so a rebuilt image never
        # reaches the node. Callers that want a guaranteed roll should also pass an
        # immutable tag (SELENIUM_GRID_IMAGE_VERSION), since an unchanged job spec
        # produces no new allocations at all.
        force_pull   = true
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
SE_ROUTER_HOST="{{ .Address }}"
SE_ROUTER_PORT="{{ .Port }}"
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
{{ end -}}
SE_NODE_GRID_URL="https://${var.dc}-${var.grid}-grid.${var.dns_zone}"
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc" }}"
SE_NODE_MAX_SESSIONS="${var.max_sessions}"
SE_ENABLE_TRACING="false"
CONFIG_FILE="/local/config.toml"
GENERATE_CONFIG="true"
#SE_OPTS="--log-level FINE"
# Chrome writes its debug log here when started with --enable-logging
# (used to capture webrtc/SRTP logs; fetch via the allocation Files tab or `nomad alloc fs`)
CHROME_LOG_FILE="/alloc/logs/chrome_debug.log"
        EOF
        destination = "local/selenium.env"
        env = true
      }

      resources {
        cpu    = 4000
        memory = 7168
      }
    }
  }
}
