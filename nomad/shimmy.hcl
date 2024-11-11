variable "dc" {
  type = string
}

variable "shimmy_hostname" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${meta.pool_type}"
    value     = "general"
  }

  group "shimmy" {
    count = 1

    network {
      port "http" {
        to = 8000
      }
    }

    service {
      name = "shimmy"
      tags = ["int-urlprefix-${var.shimmy_hostname}/"]
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

    task "shimmy" {
      driver = "docker"

      template {
        data = <<EOF
#!/bin/sh
apk add --no-cache py3-pip
pip install --break-system-packages "fastapi[standard]"

tail -f /dev/null
EOF
        destination = "local/custom_init.sh"
        perms = "755"
      }

      config {
        image = "python:alpine"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/custom_init.sh:/bin/custom_init.sh"
        ]
      }
    }
  }
}