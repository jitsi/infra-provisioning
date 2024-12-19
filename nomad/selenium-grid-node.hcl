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

variable "selenium_version" {
  type = string
  default = "4.27"
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

  group "grid-node-arm" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "selenium-grid"
    }
    constraint {
      attribute  = "${meta.selenium_grid_name}"
      value     = "${var.grid}"
    }
    constraint {
      attribute  = "${attr.cpu.arch}"
      value     = "arm64"
    }

    count = 1

    network {
      port "http-chrome" {
      }
      port "vnc-chrome" {
      }
      port "no-vnc-chrome" {
      }
      port "http-firefox" {
      }
      port "vnc-firefox" {
      }
      port "no-vnc-firefox" {
      }
    }

    service {
      name = "grid-node-chrome"
      tags = ["grid-${var.grid}"]
      port = "http-chrome"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-chrome"
        interval = "10s"
        timeout  = "2s"
      }
    }
    service {
      name = "grid-node-firefox"
      tags = ["grid-${var.grid}"]
      port = "http-firefox"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-firefox"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "node-chromium" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-chromium:${var.selenium_version}"
        ports = ["http-chrome","vnc-chrome","no-vnc-chrome"]
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
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_chrome" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_chrome" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_chrome" }}"
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

    task "node-firefox" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-firefox:${var.selenium_version}"
        ports = ["http-firefox","vnc-firefox","no-vnc-firefox"]
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
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_firefox" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_firefox" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_firefox" }}"
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

  group "grid-node-x86" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "selenium-grid"
    }
    constraint {
      attribute  = "${meta.selenium_grid_name}"
      value     = "${var.grid}"
    }
    constraint {
      attribute  = "${attr.cpu.arch}"
      value     = "amd64"
    }

    count = 1

    network {
      port "http-chrome" {
      }
      port "vnc-chrome" {
      }
      port "no-vnc-chrome" {
      }
      port "http-firefox" {
      }
      port "vnc-firefox" {
      }
      port "no-vnc-firefox" {
      }
    }

    service {
      name = "grid-node-chrome"
      tags = ["grid-${var.grid}"]
      port = "http-chrome"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-chrome"
        interval = "10s"
        timeout  = "2s"
      }
    }
    service {
      name = "grid-node-firefox"
      tags = ["grid-${var.grid}"]
      port = "http-firefox"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-firefox"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "node-chrome" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-chrome:${var.selenium_version}"
        ports = ["http-chrome","vnc-chrome","no-vnc-chrome"]
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
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_chrome" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_chrome" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_chrome" }}"
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

    task "node-firefox" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-firefox:${var.selenium_version}"
        ports = ["http-firefox","vnc-firefox","no-vnc-firefox"]
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
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_firefox" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_firefox" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_firefox" }}"
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
