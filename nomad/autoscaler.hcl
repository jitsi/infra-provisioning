variable "dc" {
  type = string
}
variable "autoscaler_hostname" {
  type = string
}

variable "autoscaler_version" {
    type = string
}

variable "oci_passphrase" {
  type = string
}

variable "oci_user" {
  type = string
}

variable "oci_fingerprint" {
  type = string
}

variable "oci_tenancy" {
  type = string
}

variable "oci_key_region" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type = "service"

  group "autoscaler" {
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    count = 1
    network {
      port "http" {
        to = 8080
      }
    }
    task "autoscaler" {
      service {
        name = "autoscaler"
        tags = ["urlprefix-${var.autoscaler_hostname}/","ip-${attr.unique.network.ip-address}"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      env {
        REDIS_TLS = false
        REDIS_DB = 1
        PROTECTED_API = "true"
        DRY_RUN = "false"
        LOG_LEVEL = "debug"
        METRIC_TTL_SEC = "3600"
        ASAP_PUB_KEY_BASE_URL = "https://d4dv7jmo5uq1d.cloudfront.net/server/stage"
        ASAP_JWT_AUD = "jitsi-autoscaler"
        ASAP_JWT_ACCEPTED_HOOK_ISS = "jitsi-autoscaler-sidecar,homer"
        GROUP_CONFIG_FILE = "/config/groups.json"
        OCI_CONFIGURATION_FILE_PATH =  "/config/oci.config"
        DEFAULT_INSTANCE_CONFIGURATION_ID = "ocid1.instanceconfiguration.oc1.phx.aaaaaaaawbzx774dlgfhvo4ahvrfiidhejzcuzh7uej67ez27k5lcg3nohra"
        OCI_CONFIGURATION_PROFILE = "DEFAULT"
        DEFAULT_COMPARTMENT_ID = "ocid1.compartment.oc1..aaaaaaaakhr7wzxmpdmmsilwnsfrsv3hxvcg4s4mjbtjknvpjlz2f5d7m6eq"
        NODE_ENV = "development"
        PORT = "8080"
        INITIAL_WAIT_FOR_POOLING_MS = 120000
        CLOUD_PROVIDERS="nomad,oracle"
      }

      template {
        data = <<EOF
[DEFAULT]
user=${var.oci_user}
fingerprint=${var.oci_fingerprint}
pass_phrase=${var.oci_passphrase}
key_file=/certs/oci_api_key.pem
tenancy=${var.oci_tenancy}
region=${var.oci_key_region}
EOF
        destination = "local/oci.config"
        perms = "600"
      }

      template {
        data = <<TILLEND
{
  "groupEntries": [
  ]
}
TILLEND
        destination = "local/groups.json"
      }
      template {
        data = <<TILLEND
{{ range $index, $item := service "redis-master" -}}
    {{ scratch.SetX "redis" $item  -}}
{{ end -}}
{{ with scratch.Get "redis" -}}
REDIS_HOST="{{ .Address }}"
REDIS_PORT="{{ .Port }}"
{{ end -}}
TILLEND
        destination = "local/autoscaler.env"
        env = true
      }
      config {
        image = "jitsi/autoscaler:${var.autoscaler_version}"
        ports = ["http"]
        volumes = [
          "local/groups.json:/config/groups.json",
          "/opt/jitsi/certs:/certs",
          "local/oci.config:/config/oci.config",
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
