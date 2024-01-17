variable "dc" {
  type = string
}

variable "oracle_s3_namespace" {
    type = string
}

variable "oracle_region" {
    type = string
}

variable "download_repo_bucket" {
    type = string
    default = "download-repo"
}

variable "download_repo_hostname" {
    type = string
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

    volume "s3fs-passwd" {
      type      = "host"
      read_only = true
      source    = "s3fs-passwd"
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

      volume_mount {
        volume      = "s3fs-passwd"
        destination = "/etc/s3fs-passwd"
        read_only   = true
      }

      resources {
        cpu    = 4000
        memory = 1000
      }

      template {
        perms = 644
        destination = "local/site.conf"
        data = <<EOF
server {
    listen 80 default_server;
    server_name localhost;
    root /mnt/download-repo/repo;

    location /health {        
        access_log    off;

        alias /mnt/download-repo/health;
    }

    location / {
        autoindex on;
    }
}
EOF
      }

      template {
        perms = 755
        destination = "local/mount.sh"
        data = <<EOF
#!/bin/bash

mkdir -p /mnt/download-repo
rm -rf /mnt/download-repo/repo
cp /etc/s3fs-passwd /etc/.s3fs-passwd
chown root:root /etc/.s3fs-passwd
chmod 0600 /etc/.s3fs-passwd
echo 's3fs#${var.download_repo_bucket} /mnt/download-repo fuse _netdev,passwd_file=/etc/.s3fs-passwd,url=https://${var.oracle_s3_namespace}.compat.objectstorage.${var.oracle_region}.oraclecloud.com,nomultipart,use_path_request_style,endpoint=${var.oracle_region},allow_other,umask=000 0 0' >> /etc/fstab

mount /mnt/download-repo
EOF

      }
    }
  }
}