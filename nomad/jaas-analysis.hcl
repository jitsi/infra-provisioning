variable "dc" {
  type = string
}

variable "jaas_analysis_hostname" {
  type = string
}

variable "jaas_analysis_version" {
  type = string
  default = "latest"
}

variable "jaas_analysis_count" {
  type = number
  default = 1
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 50

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "jaas-analysis" {
    count = var.jaas_analysis_count

    constraint {
      attribute  = "${meta.pool_type}"
      operator   = "set_contains_any"
      value      = "consul,general"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "consul"
      weight     = -50
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "general"
      weight     = 100
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    network {
      port "http" {
        to = 8080
      }
    }

    task "jaas-analysis" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "jitsi/jaas-analysis:${var.jaas_analysis_version}"
        force_pull = false
        ports = ["http"]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
PORT=8080
NODE_ENV={{ env "meta.environment" }}
ENVIRONMENT={{ env "meta.environment" }}
DATACENTER=${var.dc}
REGION={{ env "meta.cloud_region" }}

# Add your service-specific environment variables here
# Example database connections, API keys, etc.
{{ with secret "secret/default/jaas-analysis/config" }}
DATABASE_URL={{ .Data.data.database_url }}
API_KEY={{ .Data.data.api_key }}
{{ end }}
EOF
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "jaas-analysis"
        tags = ["int-urlprefix-${var.jaas_analysis_hostname}/"]
        port = "http"
        
        check {
          name     = "alive"
          type     = "http"
          path     = "/health"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
