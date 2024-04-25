variable "dc" {
  type = string
}

variable "oracle_region" {
    type = string
}

variable "oracle_s3_namespace" {
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

  group "docker-registry" {
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
        to = 5000
      }
    }

    task "docker-registry" {
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
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }

      vault {
        change_mode = "noop"
        
      }

      driver = "docker"

      config {
        image = "registry:latest"
        ports = ["http"]
      }

      env {
        REGISTRY_LOG_LEVEL="debug"
        REGISTRY_STORAGE="s3"
        REGISTRY_STORAGE_S3_BUCKET="ops-repo"
        REGISTRY_STORAGE_S3_ROOTDIRECTORY="/registry"
        REGISTRY_STORAGE_S3_REGION = "${var.oracle_region}"
        REGISTRY_STORAGE_S3_REGIONENDPOINT = "https://${var.oracle_s3_namespace}.compat.objectstorage.${meta.cloud_region}.oraclecloud.com"
        REGISTRY_STORAGE_S3_FORCEPATHSTYLE = "true"
        REGISTRY_STORAGE_S3_V4AUTH = "true"
        REGISTRY_STORAGE_S3_SECURE = "true"
        REGISTRY_STORAGE_S3_ENCRYPT = "false"
        REGISTRY_STORAGE_DELETE_ENABLED = "true"
        REGISTRY_AUTH = "htpasswd"
        REGISTRY_AUTH_HTPASSWD_PATH  = "/secrets/auth-htpasswd"
        REGISTRY_AUTH_HTPASSWD_REALM = "Registry"
        REGISTRY_HTTP_SECRET = "registrysecret"
      }

      template {
        data = <<EOF
{{ with secret "secret/default/docker-registry/s3" -}}
REGISTRY_STORAGE_S3_ACCESSKEY="{{ .Data.data.access_key }}"
REGISTRY_STORAGE_S3_SECRETKEY="{{ .Data.data.secret_key }}"
{{ end -}}
        EOF
        destination = "secrets/env"
        env = true
      }

      template {
        data = <<EOF
{{ range $index, $item := service "master.resec-redis" -}}
    {{ scratch.SetX "redis" $item  -}}
{{ end -}}
{{ with scratch.Get "redis" -}}
REGISTRY_CACHE_BLOBDESCRIPTOR="redis"
REGISTRY_REDIS_ADDR="{{ .Address }}:{{ .Port }}"
REGISTRY_REDIS_DB="3"
REGISTRY_REDIS_TLS_ENABLED="false"
{{ end -}}

        EOF
        destination = "local/registry.env"
        env = true
      }

      template {
        change_mode = "noop"
        destination = "/secrets/auth-htpasswd"

        data = <<EOH
{{- with secret "secret/default/docker-registry/htpasswd" }}
{{ .Data.data.username }}:{{ .Data.data.password }}
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
        cpu    = 1000
        memory = 1000
      }

    }
  }
}