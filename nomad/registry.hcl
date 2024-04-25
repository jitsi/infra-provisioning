variable "dc" {
  type = string
}

variable "oracle_region" {
    type = string
}

variable "registry_hostname" {
    type = string
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

   constraint {
     attribute = "${attr.kernel.name}"
     value     = "linux"
   }

  group "registry" {
    count = 1

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 80
      }
    }

    task "registry" {
      service {
        name = "docker-registry"
        tags = ["int-urlprefix-${var.registry_hostname}/"]
        port = "http"
        check {
          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }

          name     = "health"
          type     = "http"
          port     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"

      config {
        image = "registry:latest"
        ports = ["http"]
      }

      env {
        REGISTRY_STORAGE="s3"
        REGISTRY_STORAGE_S3_BUCKET="ops-repo"
        REGISTRY_STORAGE_S3_ROOTDIRECTORY="/registry"
        REGISTRY_STORAGE_DELETE_ENABLED = "true"
        REGISTRY_AUTH = "htpasswd"
        REGISTRY_AUTH_HTPASSWD_PATH  = "/secrets/auth-htpasswd"
        REGISTRY_AUTH_HTPASSWD_REALM = "Registry"
      }

      template {
        change_mode = "noop"
        destination = "/secrets/auth-htpasswd"

        data = <<EOH
{{ with secret "secret/data/registry/htpasswd" }}
{{ .Data.data.username }}:{{ .Data.data.password | md5sum }}
{{ end -}}
EOH
      }

      // eventually decide if this is going to be a volume mount or a bucket
      // volume_mount {
      //   volume      = "registry"
      //   destination = "/registry/data"
      //   read_only   = false
      // }

      resources {
        cpu    = 9000
        memory = 1000
      }

    }
  }
}