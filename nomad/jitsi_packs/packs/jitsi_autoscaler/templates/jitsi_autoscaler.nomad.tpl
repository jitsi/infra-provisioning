variable "autoscaler_hostname" {
  type = string
  default = "[[ var "hostname" . ]]"
}

job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"

  spread {
    attribute = "${node.unique.id}"
  }

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  group "autoscaler" {
    count = [[ var "count" . ]]

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "[[ var "pool_type" . ]]"
    }

    network {
      port "http" {
        to = 8080
      }
      port "metrics" {
        to = 8081
      }
    }

    [[ if var "register_service" . ]]
    service {
      name = "autoscaler"
      tags = [  "int-urlprefix-${var.autoscaler_hostname}/","urlprefix-${var.autoscaler_hostname}/","ip-${attr.unique.network.ip-address}" ]
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        port     = "metrics"
        interval = "10s"
        timeout  = "2s"
      }
      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
    }
    [[ end ]]

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    task "autoscaler" {
      driver = "docker"

      config {
        image = "jitsi/autoscaler:[[ var "version" . ]]"
        ports = ["http","metrics"]
        volumes = [
          "local/groups.json:/config/groups.json",
          "[[ var "local_certs_path" . ]]:/certs",
[[ if var "enable_oci" . ]]
          "local/oci.config:/config/oci.config",
[[ end ]]
        ]
      }

      env {
        [[ if not (var "redis_from_consul" .) -]]
        REDIS_HOST = "[[ var "redis_host" . ]]"
        REDIS_PORT = "[[ var "redis_port" . ]]"
        [[- end ]]
        REDIS_TLS = [[ var "redis_tls" . ]]
        REDIS_DB = 1
        PROTECTED_API = "true"
        DRY_RUN = "false"
        LOG_LEVEL = "debug"
        METRIC_TTL_SEC = "3600"
        ASAP_PUB_KEY_BASE_URL = "[[ var "asap_base_url" . ]]"
        ASAP_JWT_AUD = "[[ var "asap_jwt_aud" . ]]"
        ASAP_JWT_ACCEPTED_HOOK_ISS = "[[ var "asap_accepted_hook_iss" . ]]"
        GROUP_CONFIG_FILE = "/config/groups.json"
[[ if var "enable_oci" . ]]
        OCI_CONFIGURATION_FILE_PATH =  "/config/oci.config"
[[ end ]]
        DEFAULT_INSTANCE_CONFIGURATION_ID = "[[ var "oci.default_instance_configuration_id" . ]]"
        OCI_CONFIGURATION_PROFILE = "DEFAULT"
        DEFAULT_COMPARTMENT_ID = "[[ var "oci.compartment_id" . ]]"
        NODE_ENV = "development"
        PORT = "8080"
        METRICS_PORT = "8081"
        INITIAL_WAIT_FOR_POOLING_MS = 120000
        CLOUD_PROVIDERS="[[ if var "enable_nomad" . ]]nomad[[ end ]],[[ if var "enable_oci" . ]]oracle[[ end ]]"
      }

[[ if var "enable_oci" . ]]
      template {
        data = <<EOF
[DEFAULT]
user=[[ var "oci.user" . ]]
fingerprint=[[ var "oci.fingerprint" . ]]
pass_phrase=[[ var "oci.passphrase" . ]]
key_file=/certs/oci_api_key.pem
tenancy=[[ var "oci.tenancy" . ]]
region=[[ var "oci.region" . ]]
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
[[ end ]]

[[ if var "redis_from_consul" . -]]
      template {
        data = <<TILLEND
{{ range $index, $item := service "[[ var "redis_service_name" . ]]" -}}
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
[[ end -]]

[[ template "resources" (var "resources" .) ]]

    }
  }
}
