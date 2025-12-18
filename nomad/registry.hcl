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

variable "registry_mode" {
    type = string
    default = "dhmirror"
}

variable "registry_redis_db" {
    type = string
    default = "3"
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
      operator     = "set_contains_any"
      value    = "consul,general"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "consul"
      weight    = -100
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value     = "general"
      weight    = 100
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
      port "debug" {
        to = 5001
      }
    }

    # only need this in the case of dhmirror but it's easier to just always have it
    ephemeral_disk {
      migrate = true
      size    = 20000
      sticky  = true
    }

    task "docker-registry" {
      service {
        name = "docker-${var.registry_mode}"
        tags = ["int-urlprefix-${var.registry_hostname}/","ip-${attr.unique.network.ip-address}"]
        port = "http"
        meta {
          metrics_port = "${NOMAD_HOST_PORT_debug}"
          metrics_path = "/metrics"
        }
        check {
          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }

          name     = "health"
          type     = "http"
          port     = "debug"
          path     = "/metrics"
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
        ports = ["http","debug"]
      }

      env {
        REGISTRY_LOG_LEVEL="info"
        REGISTRY_HTTP_HOST="https://${var.registry_hostname}"
        // REGISTRY_AUTH =
        // REGISTRY_AUTH = "htpasswd"
        // REGISTRY_AUTH_HTPASSWD_PATH  = "/secrets/auth-htpasswd"
        // REGISTRY_AUTH_HTPASSWD_REALM = "Registry"
        REGISTRY_HTTP_SECRET = "registrysecret"
        REGISTRY_HTTP_DEBUG_ADDR = ":5001"
        REGISTRY_HTTP_DEBUG_PROMETHEUS_ENABLED = "true"
        REGISTRY_HTTP_DEBUG_PROMETHEUS_PATH = "/metrics"
        OTEL_TRACES_EXPORTER="none"
        OTEL_SDK_DISABLED="true"
      }

      template {
        data = <<EOF
{{- if eq "${var.registry_mode}" "registry" }}
REGISTRY_STORAGE="s3"
REGISTRY_STORAGE_S3_BUCKET="ops-repo"
REGISTRY_STORAGE_S3_ROOTDIRECTORY="/registry"
REGISTRY_STORAGE_S3_REGION="${var.oracle_region}"
REGISTRY_STORAGE_S3_REGIONENDPOINT="https://${var.oracle_s3_namespace}.compat.objectstorage.${var.oracle_region}.oraclecloud.com"
REGISTRY_STORAGE_S3_FORCEPATHSTYLE="true"
REGISTRY_STORAGE_S3_SECURE="true"
REGISTRY_STORAGE_DELETE_ENABLED="true"
{{ with secret "secret/default/docker-registry/s3" -}}
AWS_ACCESS_KEY_ID="{{ .Data.data.access_key }}"
AWS_SECRET_ACCESS_KEY="{{ .Data.data.secret_key }}"
{{ end -}}
{{ end -}}

{{- if eq "${var.registry_mode}" "dhmirror" }}
REGISTRY_STORAGE="filesystem"
REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY="/local/registry"
REGISTRY_PROXY_REMOTEURL="https://registry-1.docker.io"
{{ with secret "secret/default/docker-registry/dockerhub" -}}
REGISTRY_PROXY_USERNAME="{{ .Data.data.username }}"
REGISTRY_PROXY_PASSWORD="{{ .Data.data.password }}"
{{ end -}}
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
REGISTRY_REDIS_ADDR="{{ .Address }}:{{ .Port }}"
REGISTRY_REDIS_DB="${var.registry_redis_db}"
{{ end -}}

        EOF
        destination = "local/registry.env"
        env = true
      }

//       template {
//         change_mode = "noop"
//         destination = "/secrets/auth-htpasswd"

//         data = <<EOH
// {{- with secret "secret/default/docker-registry/htpasswd" }}
// {{ .Data.data.username }}:{{ .Data.data.password }}
// {{ end -}}
// EOH
//       }

      // eventually decide if this is going to be a volume mount or a bucket
      // volume_mount {
      //   volume      = "registry"
      //   destination = "/registry/data"
      //   read_only   = false
      // }

      resources {
        cpu    = 512
        memory = 4096
      }

    }
  }
}