variable "dc" {
  type = string
}

variable "environment" {
  type = string
}

variable "dns_zone" {
  type = string
  default = "jitsi.net"
}

variable "app_version" {
  type = string
  default = "latest"
}

variable "log_level" {
  type = string
  default = "INFO"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  update {
    max_parallel = 1  
    stagger = "2m"
  }

  group "multitrack-recorder" {
    count = 1

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 8989
      }
    }

    task "multitrack-recorder" {
      vault {
        change_mode = "noop"
      }
      service {
        name = "multitrack-recorder"
        tags = [
          "ip-${attr.unique.network.ip-address}",
          "int-urlprefix-${var.dc}-jmr.${var.dns_zone}/record/",
          "int-urlprefix-jmr.${var.dns_zone}/record/",
        ]
        port = "http"
        check {
          // check_restart {
          //   limit = 3
          //   grace = "90s"
          //   ignore_warnings = false
          // }

          name     = "health"
          type     = "http"
          port     = "http"
          path     = "/metrics"
          interval = "10s"
          timeout  = "2s"
        }
        meta {
          metrics_port = "${NOMAD_HOST_PORT_http}"
          metrics_path = "/metrics"
        }
      }
    
      driver = "docker"

      config {
        force_pull = "false"
        image = "jitsi/jitsi-multitrack-recorder:${var.app_version}"
        ports = ["http"]
        volumes = ["${NOMAD_ALLOC_DIR}/data:/data"]
      }

      env {
        LOG_LEVEL = "${var.log_level}"
      }

      resources {
        cpu    = 1000
        memory = 1000
      }

    }
  }
}
