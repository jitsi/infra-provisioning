    task "ingress-cloudprober" {
      service {
        name = "oscar"
        tags = ["int-urlprefix-${var.oscar_hostname}/","ip-${attr.unique.network.ip-address}"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      template {
          data = <<EOH
probe {
  name: "ops-repo"
  type: HTTP
  targets {
    host_names: "ops-repo.jitsi.net"
  }
  interval_msec: 5000
  timeout_msec: 2000

  http_probe {
    protocol: HTTPS
    relative_url: "/health"
  }
}
EOH
          destination = "local/cloudprober.cfg"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
        ]
      }
      resources {
          cpu = 2000
          memory = 256
      }
    }
  }
}