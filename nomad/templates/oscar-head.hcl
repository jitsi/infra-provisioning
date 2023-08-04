variable "pool_type" {
  type = string
  default = "general"
}

variable "dc" {
  type = string
}

variable "oscar_hostname" {
  type = string
}

variable "domain" {
  type = string
}

variable "region" {
  type = string
}

variable "cloudprober_version" {
  type = string
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = [var.dc]
  type = "service"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  meta {
    cloudprober_version = "${var.cloudprober_version}"
  }

  group "synthetics" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 9313 
      }
    }
