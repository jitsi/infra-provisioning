variable "dc" {
  type = string
}
variable "grid" {
  type = string
}
variable "registry_prefix" {
  type = string
  default = ""
}

variable "max_sessions" {
  type = number
  default = 1
}

variable "selenium_version" {
  type = string
  default = "4.27"
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = [var.dc]

  type        = "system"

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "grid-node-arm" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "selenium-grid"
    }
    constraint {
      attribute  = "${meta.selenium_grid_name}"
      value     = "${var.grid}"
    }
    constraint {
      attribute  = "${attr.cpu.arch}"
      value     = "arm64"
    }

    count = 1

    network {
      port "http-chrome" {
      }
      port "vnc-chrome" {
      }
      port "no-vnc-chrome" {
      }
      port "http-firefox" {
      }
      port "vnc-firefox" {
      }
      port "no-vnc-firefox" {
      }
    }

    service {
      name = "grid-node-chrome"
      tags = ["grid-${var.grid}"]
      port = "http-chrome"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-chrome"
        interval = "10s"
        timeout  = "2s"
      }
    }
    service {
      name = "grid-node-firefox"
      tags = ["grid-${var.grid}"]
      port = "http-firefox"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-firefox"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "node-chromium" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-chromium:${var.selenium_version}"
        ports = ["http-chrome","vnc-chrome","no-vnc-chrome"]
        volumes = [
          "/opt/jitsi/jitsi-meet-torture:/usr/share/jitsi-meet-torture:ro",
        ]

        # 2gb shm
        shm_size = 2147483648
      }

      template {
        data = <<EOF
{{ range service "grid-${var.grid}.grid-hub" -}}
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_chrome" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_chrome" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_chrome" }}"
SE_ENABLE_TRACING="false"
#SE_OPTS="--log-level FINE"
        EOF
        destination = "local/selenium.env"
        env = true
      }
      resources {
        cpu    = 4000
        memory = 6144
      }
    }

    task "node-firefox" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-firefox:${var.selenium_version}"
        ports = ["http-firefox","vnc-firefox","no-vnc-firefox"]
        volumes = [
          "/opt/jitsi/jitsi-meet-torture:/usr/share/jitsi-meet-torture:ro",
        ]

        # 2gb shm
        shm_size = 2147483648
      }

      template {
        data = <<EOF
{{ range service "grid-${var.grid}.grid-hub" -}}
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_firefox" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_firefox" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_firefox" }}"
SE_ENABLE_TRACING="false"
#SE_OPTS="--log-level FINE"
        EOF
        destination = "local/selenium.env"
        env = true
      }
      resources {
        cpu    = 4000
        memory = 6144
      }
    }
  }

  group "grid-node-x86" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "selenium-grid"
    }
    constraint {
      attribute  = "${meta.selenium_grid_name}"
      value     = "${var.grid}"
    }
    constraint {
      attribute  = "${attr.cpu.arch}"
      value     = "amd64"
    }

    count = 1

    network {
      port "http-chrome" {
      }
      port "vnc-chrome" {
      }
      port "no-vnc-chrome" {
      }
      port "http-docker" {
      }
      port "vnc-docker" {
      }
      port "no-vnc-docker" {
      }
    }

    service {
      name = "grid-node-chrome"
      tags = ["grid-${var.grid}"]
      port = "http-chrome"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-chrome"
        interval = "10s"
        timeout  = "2s"
      }
    }
    service {
      name = "grid-node-docker"
      tags = ["grid-${var.grid}"]
      port = "http-docker"

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http-docker"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "node-chrome" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-chrome:${var.selenium_version}"
        ports = ["http-chrome","vnc-chrome","no-vnc-chrome"]
        volumes = [
          "/opt/jitsi/jitsi-meet-torture:/usr/share/jitsi-meet-torture:ro",
        ]

        # 2gb shm
        shm_size = 2147483648
      }

      template {
        data = <<EOF
{{ range service "grid-${var.grid}.grid-hub" -}}
SE_HUB_HOST="{{ .Address }}"
SE_HUB_PORT="{{ .Port }}"
SE_EVENT_BUS_HOST="{{ .Address }}"
SE_EVENT_BUS_PUBLISH_PORT="{{ .ServiceMeta.publish_port }}"
SE_EVENT_BUS_SUBSCRIBE_PORT="{{ .ServiceMeta.subscribe_port }}"
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_chrome" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_chrome" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_chrome" }}"
SE_ENABLE_TRACING="false"
#SE_OPTS="--log-level FINE"
        EOF
        destination = "local/selenium.env"
        env = true
      }
      resources {
        cpu    = 4000
        memory = 6144
      }
    }

    task "node-docker" {
      driver = "docker"

      config {
        image        = "${var.registry_prefix}selenium/node-docker:${var.selenium_version}"
        ports = ["http-docker","vnc-docker","no-vnc-docker"]
        volumes = [
          "/opt/jitsi/jitsi-meet-torture:/usr/share/jitsi-meet-torture:ro",
          "local/config.toml:/opt/selenium/config.toml",
          "/var/run/docker.sock:/var/run/docker.sock",
        ]

        # 2gb shm
        shm_size = 2147483648
      }

      template {
        data = <<EOF
#!/usr/bin/python3
import sys
import os
import logging
import subprocess
import time

from supervisor.childutils import listener

def main(args):
    logging.basicConfig(stream=sys.stderr, level=logging.DEBUG, format='%(asctime)s %(levelname)s %(filename)s: %(message)s')
    logger = logging.getLogger("supervisord-watchdog")
    debug_mode = True if 'DEBUG' in os.environ else False

    while True:
        logger.info("Listening for events...")
        headers, body = listener.wait(sys.stdin, sys.stdout)
        body = dict([pair.split(":") for pair in body.split(" ")])

        logger.debug("Headers: %r", repr(headers))
        logger.debug("Body: %r", repr(body))
        logger.debug("Args: %r", repr(args))

        if debug_mode: continue

        try:
            if headers["eventname"] == "PROCESS_STATE_FATAL":
                logger.info("Process entered FATAL state...")
                if not args or body["processname"] in args:
                    logger.error("Killing off supervisord instance ...")
                    res = subprocess.call(["/usr/bin/pkill", "-15", "supervisord"], stdout=sys.stderr)
                    logger.info("Sent TERM signal to init process")
                    time.sleep( 5 )
                    logger.critical("Why am I still alive? Send KILL to all processes...")
                    res = subprocess.call(["/bin/kill", "-9", "-1"], stdout=sys.stderr)
        except Exception as e:
            logger.critical("Unexpected Exception: %s", str(e))
            listener.fail(sys.stdout)
            exit(1)
        else:
            listener.ok(sys.stdout)

if __name__ == '__main__':
    main(sys.argv[1:])
EOF
        destination = "local/supervisord-watchdog"
        perms = "755"

      }

      template {
        data = <<EOF
#!/bin/bash
sleep 10
tail -f /tmp/selenium-grid-docker-stdout*.log >> /proc/1/fd/1 &
tail -f /tmp/selenium-grid-docker-stderr*.log >> /proc/1/fd/1 &
wait
EOF
        destination = "local/tail-grid-logs.sh"
        perms = "755"
      }

      template {
        data = <<EOF
; Documentation of this file format -> http://supervisord.org/configuration.html

; Priority 0 - socat 5 - selenium-docker

[program:socat]
priority=0
command=/opt/bin/start-socat.sh
autostart=true
autorestart=false
startsecs=0
startretries=0

[program:selenium-grid-docker]
priority=5
command=/opt/bin/start-selenium-grid-docker.sh
autostart=true
autorestart=true
startsecs=0
startretries=3

[program:selenium-grid-logs]
priority=6
command=/local/tail-grid-logs.sh
autostart=true
autorestart=false
startsecs=0
startretries=0

[eventlistener:supervisord-watchdog]
command=/local/supervisord-watchdog
events=PROCESS_STATE_FATAL

;Logs (all Hub activity redirected to stdout so it can be seen through "docker logs"
;cannot use with eventlistener
;redirect_stderr=true
stdout_logfile=/proc/1/fd/1
stdout_logfile_maxbytes=0
EOF
        destination = "local/selenium-grid-docker.conf"
      }

      template {
        data = <<EOF
[node]
detect-drivers = false
max-sessions = ${var.max_sessions}

[docker]
# Configs have a mapping between the Docker image to use and the capabilities that need to be matched to
# start a container with the given image.
configs = [
    "jitsi/selenium-standalone-firefox:daily-2024-12-19", "{\"browserName\": \"firefox\"}",
    "jitsi/selenium-standalone-firefox:beta-daily-2024-12-19", "{\"browserName\": \"firefox-beta\"}",
    "jitsi/selenium-standalone-chrome:beta-daily-2024-12-19", "{\"browserName\": \"chrome-beta\"}"
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

video-image = "selenium/video:ffmpeg-6.1-20240402"

# Uncomment the following section if you are running the node on a separate VM
# Fill out the placeholders with appropriate values
[server]
host = "{{env "attr.unique.network.ip-address" }}"
port = {{ env "NOMAD_HOST_PORT_http_docker" }}
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
SE_NODE_GRID_URL="http://{{ .Address }}:{{ .Port }}"
{{ end -}}
SE_NODE_HOST="{{env "attr.unique.network.ip-address" }}"
SE_NODE_PORT="{{ env "NOMAD_HOST_PORT_http_docker" }}"
SE_VNC_PORT="{{ env "NOMAD_HOST_PORT_vnc_docker" }}"
SE_NO_VNC_PORT="{{ env "NOMAD_HOST_PORT_no_vnc_docker" }}"
SE_ENABLE_TRACING="false"
#SE_OPTS="--log-level FINE"
        EOF
        destination = "local/selenium.env"
        env = true
      }
      resources {
        cpu    = 4000
        memory = 2048
      }
    }
  }
}
