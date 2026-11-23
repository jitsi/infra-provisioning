variable "dc" {
  type = string
}

variable "tailscale_hostname" {
  type = string
}

variable "tailscale_version" {
  type = string
  default = "latest"
}

variable "tailscale_count" {
  type = number
  default = 1
}

variable "tailscale_auth_key" {
  type = string
  description = "Headscale auth key for automatic device registration"
  default = ""
}

variable "headscale_url" {
  type = string
  description = "Headscale server URL"
  default = ""
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 50

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "tailscale" {
    count = var.tailscale_count

    constraint {
      attribute  = "${meta.pool_type}"
      operator   = "set_contains_any"
      value      = "consul,general"
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "consul"
      weight     = -50
    }

    affinity {
      attribute  = "${meta.pool_type}"
      value      = "general"
      weight     = 100
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    network {
      mode = "host"
      port "http" {
        static = 8080
        to = 8080
      }
    }

    task "tailscale" {
      driver = "docker"

      vault {
        change_mode = "restart"
      }

      config {
        image = "tailscale/tailscale:${var.tailscale_version}"
        force_pull = false
        network_mode = "host"
        cap_add = ["NET_ADMIN", "NET_RAW"]
        privileged = true
        volumes = [
          "/dev/net/tun:/dev/net/tun",
          "local/start-tailscale.sh:/start-tailscale.sh"
        ]
        entrypoint = ["/bin/sh", "/start-tailscale.sh"]
      }

      template {
        destination = "local/start-tailscale.sh"
        perms = "755"
        data = <<EOF
#!/bin/sh
set -e

echo "Starting Tailscale daemon..."
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &
TAILSCALED_PID=$!

# Wait for tailscaled to start
sleep 5

echo "Connecting to network..."
if [ -n "$TS_LOGIN_SERVER" ]; then
    echo "Using Headscale server: $TS_LOGIN_SERVER"
    tailscale up --login-server="$TS_LOGIN_SERVER" --authkey="$TS_AUTHKEY" --accept-routes --accept-dns=false
else
    echo "Using Tailscale.com"
    tailscale up --authkey="$TS_AUTHKEY" --accept-routes --accept-dns=false
fi

echo "Tailscale connected successfully"
tailscale status

# Keep the daemon running
wait $TAILSCALED_PID
EOF
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
TS_STATE_DIR=/var/lib/tailscale
TS_SOCKET=/var/run/tailscale/tailscaled.sock
TS_USERSPACE=true
{{ if var.headscale_url != "" }}
TS_LOGIN_SERVER=${var.headscale_url}
{{ end }}
{{ if var.tailscale_auth_key != "" }}
TS_AUTHKEY=${var.tailscale_auth_key}
{{ else }}
{{ with secret "secret/default/headscale/config" }}
TS_AUTHKEY={{ .Data.data.auth_key }}
{{ if .Data.data.login_server }}
TS_LOGIN_SERVER={{ .Data.data.login_server }}
{{ end }}
{{ end }}
{{ end }}
DATACENTER=${var.dc}
REGION={{ env "meta.cloud_region" }}
NOMAD_ALLOC_ID={{ env "NOMAD_ALLOC_ID" }}
EOF
      }

      resources {
        cpu    = 200
        memory = 128
      }

      service {
        name = "tailscale"
        tags = ["int-urlprefix-${var.prometheus_hostname}/"]
        port = "http"
        
        check {
          name     = "tailscale-status"
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "tailscale status --json > /dev/null 2>&1"]
          interval = "30s"
          timeout  = "10s"
        }
      }
    }

    task "tailscale-web" {
      driver = "docker"
      
      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image = "nginx:alpine"
        ports = ["http"]
        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf"
        ]
      }

      template {
        destination = "local/nginx.conf"
        data = <<EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 8080;
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        location /status {
            proxy_pass http://100.100.100.100:8080/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        location / {
            return 200 "Tailscale VPN Gateway\n";
            add_header Content-Type text/plain;
        }
}
}
EOF
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
