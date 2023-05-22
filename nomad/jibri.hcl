variable "pool_type" {
  type = string
  default = "general"
}

variable jibri_recorder_password {
    type = string
    default = "replaceme_recorder"
}

variable jibri_xmpp_password {
    type = string
    default = "replaceme_jibri"
}

variable "jibri_tag" {
  type = string
}

variable "dc" {
  type = string
}

variable "environment" {
    type = string
}

variable "domain" {
    type = string
}


# This declares a job named "docs". There can be exactly one
# job declaration per job file.
job "[JOB_NAME]" {
  # Specify this job should run in the region named "global". Regions
  # are defined by the Nomad servers' configuration.
  region = "global"

  datacenters = ["${var.dc}"]

  # Run this job as a "service" type. Each job type has different
  # properties. See the documentation below for more examples.
  type = "service"

  # Specify this job to have rolling updates, two-at-a-time, with
  # 30 second intervals.
  update {
    stagger      = "30s"
    max_parallel = 2
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "jibri" {

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "${var.pool_type}"
    }

    count = 1

    network {
      # This requests a dynamic port named "http". This will
      # be something like "46283", but we refer to it via the
      # label "http".
      port "http" {
        to = 2222
      }
    }

    task "jibri" {
      driver = "docker"

      config {
        image        = "jitsi/jibri:${var.jibri_tag}"
        privileged = true
        ports = ["http"]
      }

      env {
        XMPP_ENV_NAME = "${var.environment}"
        XMPP_DOMAIN = "${var.domain}"
        PUBLIC_URL="https://${var.domain}/"
        JIBRI_RECORDER_USER = "recorder"
        JIBRI_RECORDER_PASSWORD = "${var.jibri_recorder_password}"
        JIBRI_XMPP_USER = "jibri"
        JIBRI_XMPP_PASSWORD = "${var.jibri_xmpp_password}"
        # Internal XMPP domain for authenticated services
        XMPP_AUTH_DOMAIN = "auth.${var.domain}"
        # XMPP domain for the MUC
        XMPP_MUC_DOMAIN = "conference.${var.domain}"
        # XMPP domain for the internal MUC used for jibri, jigasi and jvb pools
        XMPP_INTERNAL_MUC_DOMAIN = "internal.auth.${var.domain}"
        # XMPP domain for unauthenticated users
        XMPP_GUEST_DOMAIN = "guest.${var.domain}"
        # XMPP domain for the jibri recorder
        XMPP_RECORDER_DOMAIN = "recorder.${var.domain}"
        DISPLAY=":0"
        JIBRI_INSTANCE_ID = "${NOMAD_SHORT_ALLOC_ID}"
      }

      template {
        data = <<EOF
{{ range $index, $item := service "signal" -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.shard $item  -}}
{{ end -}}
{{ range $index, $item := service "all" -}}
    {{ scratch.MapSetX "shards" .ServiceMeta.domain $item  -}}
{{ end -}}
XMPP_SERVER="{{ range $sindex, $item := scratch.MapValues "shards" -}}{{ if gt $sindex 0 -}},{{end}}{{ .Address }}:{{ with .ServiceMeta.prosody_client_port}}{{.}}{{ else }}5222{{ end }}{{ end -}}"
EOF

        destination = "local/jibri.env"
        env = true
      }

      resources {
        cpu    = 10000
        memory = 4096
        memory_max = 4096
      }
    }


  }
}