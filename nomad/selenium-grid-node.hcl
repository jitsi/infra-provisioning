variable "dc" {
  type = string
}
variable "grid" {
  type = string
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "service"

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "node" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    count = 1

    network {
      port "http" {
      }
    }

    service {
      name = "grid-node"
      tags = ["grid-${var.grid}"]
      port = "http"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "node" {
      driver = "docker"

      config {
        image        = "selenium/node-docker:4.11.0-20230801"
        ports = ["http"]
        volumes = ["local/config.toml:/opt/bin/config.toml","/var/run/docker.sock:/var/run/docker.sock"]

        # 2gb shm
        shm_size = 2147483648
      }
      template {
        data = <<EOF
[docker]
# Configs have a mapping between the Docker image to use and the capabilities that need to be matched to
# start a container with the given image.
configs = [
    "selenium/standalone-firefox:4.11.0-20230801", "{\"browserName\": \"firefox\"}",
    "selenium/standalone-chrome:4.11.0-20230801", "{\"browserName\": \"chrome\"}",
    "selenium/standalone-edge:4.11.0-20230801", "{\"browserName\": \"MicrosoftEdge\"}"
    ]

# URL for connecting to the docker daemon
# Most simple approach, leave it as http://127.0.0.1:2375, and mount /var/run/docker.sock.
# 127.0.0.1 is used because interally the container uses socat when /var/run/docker.sock is mounted 
# If var/run/docker.sock is not mounted: 
# Windows: make sure Docker Desktop exposes the daemon via tcp, and use http://host.docker.internal:2375.
# macOS: install socat and run the following command, socat -4 TCP-LISTEN:2375,fork UNIX-CONNECT:/var/run/docker.sock,
# then use http://host.docker.internal:2375.
# Linux: varies from machine to machine, please mount /var/run/docker.sock. If this does not work, please create an issue.
url = "http://127.0.0.1:2375"
# Docker image used for video recording
video-image = "selenium/video:ffmpeg-4.3.1-20230801"

# Uncomment the following section if you are running the node on a separate VM
# Fill out the placeholders with appropriate values
[server]
host = "{{env "attr.unique.network.ip-address" }}"
port = {{ env "NOMAD_HOST_PORT_http" }}
EOF
        destination = "local/config.toml"
      }


      template {
        data = <<EOF
{{ range service "grid-${var.grid}.grid-hub" -}}
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http" }}"
        EOF
        destination = "local/selenium.env"
        env = true
      }
    }
  }
}
