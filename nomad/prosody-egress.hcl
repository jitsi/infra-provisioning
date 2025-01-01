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
      operator     = "set_contains_any"
      value    = "consul,general"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "consul"
      weight    = -100
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
      weight    = 100
    }

    network {
      mode = "bridge"
      port "expose" {
      }
    }

    service {
      name = "prosody-egress"
      tags = ["ip-${attr.unique.network.ip-address}"]
      port = "8062"
      meta {
        environment = "${meta.environment}"
        metrics_port = "${NOMAD_HOST_PORT_expose}"
      }

      connect {
        sidecar_service {
          proxy {
            local_service_port = 8062
            expose {
              path {
                path            = "/actuator/health"
                protocol        = "http"
                local_path_port = 8063
                listener_port   = "expose"
              }
            }
          }
        }
      }

      check {
        name     = "health"
        type     = "http"
        path     = "/actuator/health"
        port     = "expose"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "prosody-egress" {
      vault {
        change_mode = "noop"
      }
      driver = "docker"
      config {
        image        = "103425057857.dkr.ecr.us-west-2.amazonaws.com/jitsi-vo/prosody-egress:j-37"
        volumes = [
          "local/logs:/var/log/prosody-egress",
        ]
      }
      env {
        ENVIRONMENT_TYPE = "${var.environment_type}"
        STATSD_HOST = "${attr.unique.network.ip-address}"
      }
      resources {
        cpu    = 500
        memory = 2048
      }
      template {
        data = <<EOF
AWS_DEFAULT_REGION="us-west-2"
AWS_REGION="us-west-2"
{{ with secret "secret/default/prosody-egress/aws" -}}
AWS_ACCESS_KEY_ID="{{ .Data.data.access_key }}"
AWS_SECRET_ACCESS_KEY="{{ .Data.data.secret_key }}"
{{ end -}}
EOF
        destination = "secrets/aws"
        env = true
      }
    }
  }
}