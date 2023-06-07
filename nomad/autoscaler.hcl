variable "dc" {
  type = string
}
variable "autoscaler_hostname" {
  type = string
}

variable "autoscaler_version" {
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
        CLOUD_PROVIDER="nomad"
      }
      template {
        data = <<TILLEND
{
  "groupEntries": [
    {
      "name": "beta-meet-jit-si-us-phoenix-1-JibriGroup",
      "type": "jibri",
      "region": "us-phoenix-1",
      "environment": "beta-meet-jit-si",
      "compartmentId": "",
      "instanceConfigurationId": "https://beta-meet-jit-si-us-phoenix-1-nomad.jitsi.net|jibri-us-phoenix-1",
      "enableAutoScale": true,
      "enableLaunch": true,
      "gracePeriodTTLSec": 480,
      "protectedTTLSec": 600,
      "scalingOptions": {
        "minDesired": 1,
        "maxDesired": 2,
        "desiredCount": 2,
        "scaleUpQuantity": 1,
        "scaleDownQuantity": 1,
        "scaleUpThreshold": 1,
        "scaleDownThreshold": 2,
        "scalePeriod": 60,
        "scaleUpPeriodsCount": 2,
        "scaleDownPeriodsCount": 4
      },
      "cloud": "nomad"
    }
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
        ]
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
