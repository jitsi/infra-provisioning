variable "dc" {
  type = string
}

variable "oracle_s3_namespace" {
    type = string
}

variable "oracle_region" {
    type = string
}

variable "bucket" {
    type = string
    default = "download-repo"
}

variable "download_repo_hostname" {
    type = string
    default = "download.jitsi.org"
}

job "download-repo" {
  datacenters = ["${var.dc}"]

  type = "service"

   constraint {
     attribute = "${attr.kernel.name}"
     value     = "linux"
   }
  group "download-repo" {
    count = 2

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 80
      }
    }

    task "download-repo" {
      service {
        name = "download-repo"
        tags = ["urlprefix-${var.download_repo_hostname}/"]
        port = "http"
        check {
          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }

          name     = "health"
          type     = "http"
          port     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"

      vault {
        change_mode = "noop"
      }

      config {
        image = "aaronkvanmeerten/ops-repo:latest"
        force_pull = false
        ports = ["http"]
        cap_add = ["SYS_ADMIN"]
        privileged = true
        devices = [{ host_path = "/dev/fuse" }]
        volumes = [
	        "local/site.conf:/etc/nginx/sites-available/default",
          "local/mount.sh:/docker-entrypoint.d/10-mount.sh"
      	]
      }

      resources {
        cpu    = 9000
        memory = 1000
      }

      template {
        destination = "local/site.conf"
        data = <<EOF
server {
    listen 80 default_server;
    server_name localhost;
    root /mnt/ops-repo/repo;

    location /health {        
        access_log    off;

        alias /mnt/ops-repo/health;
    }

    location / {
        #             autoindex on;
        fancyindex on;              # Enable fancy indexes.
        fancyindex_exact_size off;  # Output human-readable file sizes.
        fancyindex_ignore changes mini-dinstall .db;

    }
}
EOF
      }

      template {
        destination = "secrets/s3fs-passwd"
        data = <<EOF
{{ with secret "secret/default/download-repo/s3" -}}
{{ .Data.data.access_key }}:{{ .Data.data.secret_key }}
{{ end -}}
EOF
      }
      template {
        perms = 755
        destination = "local/mount.sh"
        data = <<EOF
#!/bin/bash

cp /secrets/s3fs-passwd /etc/.s3fs-passwd
chown root:root /etc/.s3fs-passwd
chmod 0600 /etc/.s3fs-passwd
echo 's3fs#${var.bucket} /mnt/ops-repo fuse _netdev,passwd_file=/etc/.s3fs-passwd,url=https://${var.oracle_s3_namespace}.compat.objectstorage.${var.oracle_region}.oraclecloud.com,nomultipart,use_path_request_style,endpoint=${var.oracle_region},allow_other,nonempty,umask=000 0 0' >> /etc/fstab

mount /mnt/ops-repo
EOF

      }
    }
  }
}