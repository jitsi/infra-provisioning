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
          path     = "/healthz"
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
    }
  }
}
