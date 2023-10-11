variable "environment" {
    type = string
}

variable "dc" {
  type = string
}

variable "octo_region" {
    type=string
}

variable "pool_type" {
  type = string
  default = "general"
}

variable cloud_provider {
    type = string
    default = "oracle"
}

variable "aws_access_key_id" {
    type = string
    default = "replaceme"
}

variable "aws_secret_access_key" {
    type = string
    default = "replaceme"
}

variable environment_type {
    type = string
    default = "dev"
}


job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"

  meta {
    environment = "${var.environment}"
    octo_region = "${var.octo_region}"
    cloud_provider = "${var.cloud_provider}"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "prosody-egress" {
    count = 2

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    network {
      port "prosody-egress" {
        to = 8062
      }
      port "actuator" {
        to = 8063
      }
    }

    service {
      name = "prosody-egress"
      tags = ["int-urlprefix-/v1/events", "ip-${attr.unique.network.ip-address}"]
      port = "prosody-egress"
      meta {
        environment = "${meta.environment}"
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/actuator/health"
        port     = "actuator"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "prosody-egress" {
      driver = "docker"
      config {
        image        = "103425057857.dkr.ecr.us-west-2.amazonaws.com/jitsi-vo/prosody-egress:j-37"
        ports = ["prosody-egress", "actuator"]
        volumes = [
          "local/logs:/var/log/prosody-egress",
          "local/aws:/etc/prosody-egress/.aws"
        ]
      }
      env {
        ENVIRONMENT_TYPE = "${var.environment_type}"
        STATSD_HOST = "${attr.unique.network.ip-address}"
      }
      resources {
        cpu    = 1200
        memory = 2048
      }
      template {
        data = <<EOF
[default]
region = us-west-2
EOF
        destination = "local/aws/config"  
      }
      template {
        data = <<EOF
[default]
aws_access_key_id = ${var.aws_access_key_id}
aws_secret_access_key = ${var.aws_secret_access_key}
EOF
        destination = "local/aws/credentials"  
      }

    }
  }
}