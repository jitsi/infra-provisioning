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

  group "canary" {
    count = 2

    constraint {
      attribute  = "${meta.pool_type}"
      operator     = "set_contains_any"
      value    = "consul,general"
    }

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
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

    network {
      mode = "bridge"
      port "http" {
        to = 80
      }
      port "metrics" {
        to = 9113
      }
    }

    service {
      name = "canary"
      port = "http"
      tags = [
        "ip-${attr.unique.network.ip-address}",
        "urlprefix-/canary/health strip=/canary",
      ]
      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }

      meta {
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
      }
    }

    task "web-nginx-prometheus-exporter" {
      driver = "docker"
      config {
        image = "nginx/nginx-prometheus-exporter:1.4.1"
        ports = ["web-nginx-prometheus-exporter"]
      }

      env {
        SCRAPE_URI="http://localhost:888/nginx_status"
      }

    }

    task "canary" {
      driver = "docker"

      template {
        data = <<EOF
user nginx;
worker_processes auto;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  text/plain;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
        '$status $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /dev/stdout main;
    error_log /dev/stderr;
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
    listen       80;
    server_name  localhost;

    location /health {
        return 200 "OK\n";
    }
}

server {
    listen       888;
    server_name  localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
    }
}
EOF
        destination = "local/default.conf"
        perms = "644"
      }

      config {
        image = "nginx:alpine"
        force_pull = true
        ports = ["http"]
        volumes = [
          "local/nginx.conf:/etc/nginx/nginx.conf",
          "local/default.conf:/etc/nginx/conf.d/default.conf"
        ]
      }
    }
  }
}