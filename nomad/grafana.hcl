variable "dc" {
  type = string
}

variable "grafana_hostname" {
    type = string
    default  = "grafana.example.com"
}

job "grafana" {
  datacenters = ["${var.dc}"]

  type = "service"

   constraint {
     attribute = "${attr.kernel.name}"
     value     = "linux"
   }

  update {
    max_parallel = 1
    
    min_healthy_time = "10s"
    
    healthy_deadline = "8m"
    
    auto_revert = false
    
    canary = 0
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "10m"
    unlimited      = true
  }
  group "grafana" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"

      delay = "25s"

      mode = "delay"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    network {
      port "grafana_http" {
        to = 3000
      }
    }

    task "grafana" {
      driver = "docker"

      config {
        image = "grafana/grafana-oss"
        force_pull = false
        ports = ["grafana_http"]
        volumes = [ 
	        "/opt/nomad/loki/grafana/varlib:/var/lib/grafana"
        // "local/grafana/conf:/etc/grafana"
    	]
      }

      resources {
        cpu    = 1200 # 500 MHz
        memory = 300 # 256MB
      }

      env {
        GF_SERVER_DOMAIN = "${var.grafana_hostname}"
        GF_SERVER_ROOT_URL = "https://${var.grafana_hostname}/"
      }

      service {
        name = "grafana"
        tags = ["int-urlprefix-${var.grafana_hostname}/"]
        port = "grafana_http"
        check {
          name     = "alive"
          path     = "/api/health"
          type     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}