variable "environment" {
    type = string
}

variable "domain" {
    type = string
}

variable "dc" {
  type = list(string)
}

variable colibri_proxy_second_octet_regexp {
    type = string
        default = "5[2-3]"
}

variable colibri_proxy_third_octet_regexp {
    type = string
        default = "6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7]"
}

variable colibri_proxy_fourth_octet_regexp {
    type = string
        default = "25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?"
}

job "[JOB_NAME]" {
  region = "global"
  datacenters = var.dc

  type        = "service"
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

  spread {
    attribute = "${node.unique.id}"
  }

  spread {
    attribute = "${node.datacenter}"
    weight    = 100
  }

  meta {
    domain = "${var.domain}"
    environment = "${var.environment}"
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "colibri-proxy" {
    count = 2 * length(var.dc)

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
    network {
      port "nginx-colibri-proxy" {
      }
    }
    service {
      name = "colibri-proxy"
      tags = ["${var.domain}","urlprefix-${var.domain}/colibri-ws","urlprefix-${var.domain}/colibri-relay-ws"]

      port = "nginx-colibri-proxy"

      check {
        name     = "health"
        type     = "http"
        path     = "/"
        port     = "nginx-colibri-proxy"
        interval = "10s"
        timeout  = "2s"
      }
    }
    task "colibri-proxy" {
      driver = "docker"
      config {
        image        = "nginx:latest"
        ports = ["nginx-colibri-proxy"]
        volumes = ["local/nginx-conf.d:/etc/nginx/conf.d"]
      }
      meta {
        SECOND_OCTET_REGEXP = "${var.colibri_proxy_second_octet_regexp}"
        THIRD_OCTET_REGEXP = "${var.colibri_proxy_third_octet_regexp}"
        FOURTH_OCTET_REGEXP = "${var.colibri_proxy_fourth_octet_regexp}"
      }
      env {
        NGINX_PORT = "${NOMAD_HOST_PORT_nginx_colibri_proxy}"
      }

      template {
        destination = "local/nginx-conf.d/default.conf"
        change_mode = "script"
        change_script {
          command = "/usr/sbin/nginx"
          args = ["-s", "reload"]
          timeout = "30s"
          fail_on_error = true
        }

        data = <<EOF

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

{{ range $dcidx, $dc := datacenters -}}
{{ $service := print "jvb@" $dc -}}
{{ range $index, $item := service $service -}}
{{ with $item.ServiceMeta.nomad_allocation -}}
upstream 'jvb-{{ . }}' {
    zone upstreams 64K;
    server {{ $item.Address }}:{{ $item.ServiceMeta.colibri_port }};
    keepalive 2;
}
{{ end -}}
{{ end -}}
{{ end -}}

server {
    listen {{ env "NOMAD_HOST_PORT_nginx_colibri_proxy" }} default_server;
    listen  [::]:{{ env "NOMAD_HOST_PORT_nginx_colibri_proxy" }} default_server;
    server_name  {{ env "NOMAD_META_domain" }};

    #access_log  /var/log/nginx/host.access.log  main;

    root   /usr/share/nginx/html;

    location ~ ^/colibri-ws/jvb-({{ env "NOMAD_META_SECOND_OCTET_REGEXP" }})-({{ env "NOMAD_META_THIRD_OCTET_REGEXP" }})-({{ env "NOMAD_META_FOURTH_OCTET_REGEXP" }})(/?)(.*) {
        proxy_pass https://10.$1.$2.$3:443/colibri-ws/jvb-$1-$2-$3/$5$is_args$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host {{ env "NOMAD_META_domain" }};
        tcp_nodelay on;
    }


    location ~ ^/colibri-relay-ws/jvb-({{ env "NOMAD_META_SECOND_OCTET_REGEXP" }})-({{ env "NOMAD_META_THIRD_OCTET_REGEXP" }})-({{ env "NOMAD_META_FOURTH_OCTET_REGEXP" }})(/?)(.*) {
        proxy_pass https://10.$1.$2.$3:443/colibri-relay-ws/jvb-$1-$2-$3/$5$is_args$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host {{ env "NOMAD_META_domain" }};
        tcp_nodelay on;
    }

    location ~ '^/colibri-ws/(jvb-[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12})(/?)(.*)' {
        proxy_pass http://$1/colibri-ws/$1/$3$is_args$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host {{ env "NOMAD_META_domain" }};
        tcp_nodelay on;
    }

    location ~ '^/colibri-relay-ws/(jvb-[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12})(/?)(.*)' {
        proxy_pass http://$1/colibri-relay-ws/$1/$3$is_args$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host {{ env "NOMAD_META_domain" }};
        tcp_nodelay on;
    }
}
EOF
        }
    }
  }
}