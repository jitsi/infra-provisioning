variable "dc" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]
  type        = "service"
  priority    = 75

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "canary" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "canary"
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "canary" {
      driver = "docker"

      template {
        data = <<EOF
user nginx;
worker_processes auto;

error_log  /dev/null crit;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log      off;
    sendfile        on;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
EOF
        destination = "local/nginx.conf"
        perms = "644"
      }

      template {
        data = <<EOF
server {
    listen       8080;
    server_name  localhost;

    location /health {
        access_log off;
        add_header 'Content-Type' 'text/plain';
        return 200 "OK\n";
    }
}
EOF
        destination = "local/default.conf"
        perms = "644"
      }

      config {
        image = "nginx:alpine"
        ports = ["http"]
        #entrypoint = ["tail", "-f", "/dev/null"]
        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf",
          "local/default.conf:/etc/nginx/conf.d/default.conf"
        ]
      }
    }
  }
}