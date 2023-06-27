variable "dc" {
  type = string
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"

  update {
    max_parallel = 1
    stagger      = "10s"
  }

  group "cache" {
    count = 3

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    network {
      # This requests a dynamic port named "http". This will
      # be something like "46283", but we refer to it via the
      # label "http".
      port "redis_db" {
        to = 6379
      }
    }

    task "redis" {
      driver = "docker"
      config {
        image = "redis:alpine"
        command = "redis-server"
        args = [
          "/local/redis.conf"
        ]
        ports = ["redis_db"]
      }
      // Let Redis know how much memory he can use not to be killed by OOM
      template {
        data = <<EORC
maxmemory {{ env "NOMAD_MEMORY_LIMIT" | parseInt | subtract 16 }}mb
EORC
        destination   = "local/redis.conf"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }

    task "resec" {
      driver = "docker"
      config {
        image = "yotpo/resec"
      }

      env {
        CONSUL_HTTP_ADDR = "http://${attr.unique.network.ip-address}:8500"
        REDIS_ADDR = "${NOMAD_ADDR_redis_db}"
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}