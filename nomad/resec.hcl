variable "dc" {
  type = string
}

locals {
  redis = [0, 1, 2]
}

job "[JOB_NAME]" {
  region = "global"

  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 80

  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel = 1
    stagger      = "10s"
  }

  dynamic "group" {
    for_each = local.redis
    labels   = ["redis-${group.key}"]
    content {
      constraint {
        attribute  = "${meta.pool_type}"
        value     = "consul"
      }

      network {
        # This requests a dynamic port named "http". This will
        # be something like "46283", but we refer to it via the
        # label "http".
        port "redis_db" {
          to = 6379
        }
        port "metrics" {
          to = 9121
        }
      }

      volume "redis" {
        type      = "host"
        read_only = false
        source    = "redis-${group.key}"
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
        volume_mount {
          volume      = "redis"
          destination = "/data"
          read_only   = false
        }

        // Let Redis know how much memory he can use not to be killed by OOM
        template {
          data = <<EORC
maxmemory {{ env "NOMAD_MEMORY_LIMIT" | parseInt | subtract 16 }}mb
save 60 1
loglevel warning
EORC
        destination   = "local/redis.conf"
      }

        resources {
          cpu    = 500
          memory = 512
        }
      }

      task "resec" {
        driver = "docker"
        config {
          image = "aaronkvanmeerten/resec"
        }

      env {
        CONSUL_HTTP_ADDR = "http://${attr.unique.network.ip-address}:8500"
        REDIS_ADDR = "${NOMAD_ADDR_redis_db}"
        CONSUL_SERVICE_NAME = "resec-redis"
        MASTER_TAGS = "master"
        SLAVE_TAGS = "readonly"
      }

        resources {
          cpu    = 100
          memory = 64
        }
      }

      task "redis_exporter" {
        driver = "docker"
        config {
          image = "oliver006/redis_exporter"
          ports = ["metrics"]
        }
        env {
          REDIS_ADDR = "redis://${NOMAD_ADDR_redis_db}"
        }
        service {
          name = "redis-metrics"
          tags = ["ip-${attr.unique.network.ip-address}","redis-${group.key}"]
          port = "metrics"
          check {
            name     = "alive"
            type     = "http"
            path     = "/health"
            interval = "10s"
            timeout  = "2s"
          }
          meta {
            redis_index = "${group.key}"
          }
        }
      }
    }
  }
}