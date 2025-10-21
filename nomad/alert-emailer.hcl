variable "dc" {
  type = string
}

variable "region" {
  type = string
}

variable "hostname" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "docker_image_host" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "notification_email" {
  type = string
  default = "none"
}

variable "check_notification_email" {
  type = string
  default = "false"
}

variable "log_level" {
    type = string
    default = "WARN"
}

variable "http_port" {
    type = number
    default = 3000
}

variable "metrics_port" {
    type = number
    default = 8080
}

variable "image_tag" {
    type = string
    default = "latest"
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  group "alert-emailer" {
    count = 2

    constraint {
      attribute  = "${meta.pool_type}"
      operator     = "set_contains_any"
      value    = "consul,general"
    }

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "consul"
      weight     = -100
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "general"
      weight     = 100
    }

    network {
      port "http" {
        to = "${var.http_port}"
      }
      port "metrics" {
        to = "${var.metrics_port}"
      }
    }

    task "alert-emailer" {
      service {
        name = "alert-emailer"
        tags = [
          "ip-${attr.unique.network.ip-address}",
          "int-urlprefix-${var.hostname}",
        ]
        port="http"

        check {
          port     = "http"
          path     = "/health"
          type     = "http"
          name     = "alive"
          interval = "10s"
          timeout  = "2s"
        }

        meta {
          http = "${NOMAD_HOST_PORT_http}"
          metrics = "${NOMAD_HOST_PORT_metrics}"
        }
      }

      driver = "docker"

      config {
        image = "${var.docker_image_host}/alert-oci-shim:${var.image_tag}"
        force_pull = true
        ports = ["http", "metrics"]
      }
      
      env {
        COMPARTMENT_OCID="${var.compartment_ocid}"
        ORACLE_REGION="${var.region}"
        ALERT_TOPIC_NAME="${var.topic_name}"
        NOTIFICATION_EMAIL="${var.notification_email}"
        CHECK_NOTIFICATION_EMAIL="${var.check_notification_email}"
        DEBUG_LEVEL="${var.log_level}"
        PROXY_MODE = "true"
        PORT="${var.http_port}"
        METRICS_PORT="${var.metrics_port}"
        SERVICE_NAME="alert-emailer"
      }

      resources {
        cpu    = 512
        memory = 512
      }
    }
  }
}