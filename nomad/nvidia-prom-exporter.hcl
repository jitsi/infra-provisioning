variable dc {
    type = list(string)
}

job "nvidia-prom-exporter" {
  datacenters = var.dc

  type = "system"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${meta.gpu_count}"
    operator  = ">="
    value     = "1"
  }

  group "gpu-monitor" {
    count = 1

    network {
      port "metrics_gpu" {
        to = 9400
      }
    }

    task "gpu-monitor" {
      shutdown_delay = "5s"
      service {
        name = "gpu-monitor"
        tags = [
          "ip-${attr.unique.network.ip-address}"
        ]
        port = "metrics_gpu"
        check {
          name     = "health"
          type     = "http"
          port     = "metrics_gpu"
          # dcgm-exporter serves /health -- NOT /healthz. The skynet family of jobs in
          # this repo use /healthz (skynet really does define that route), and this job
          # copied the pattern onto a third-party image that does not.
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"

      config {
        # use the nvidia docker runtime
        runtime = "nvidia"
        image = "nvidia/dcgm-exporter:3.3.0-3.2.0-ubuntu22.04"
        ports = ["metrics_gpu"]
        cap_add = ["SYS_ADMIN"]
      }

      env {
        DCGM_EXPORTER_INTERVAL = "10000"
      }
      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
