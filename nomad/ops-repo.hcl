variable "dc" {
  type = string
}

variable "oracle_s3_namespace" {
    type = string
}

variable "oracle_region" {
    type = string
}

variable "ops_bucket" {
    type = string
    default = "ops-repo"
}

variable "ops_repo_hostname" {
    type = string
}

variable "ops_repo_username" {
    type = string
    default = "repo"
}

variable "ops_repo_password" {
    type = string
    default = "replaceme"
}

job "ops-repo" {
  datacenters = ["${var.dc}"]

  type = "service"

   constraint {
     attribute = "${attr.kernel.name}"
     value     = "linux"
   }
  group "ops-repo" {
    count = 2

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


    task "ops-repo" {
      service {
        name = "ops-repo"
        tags = ["int-urlprefix-${var.ops_repo_hostname}/"]
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
	        "local/htpasswd:/etc/nginx/htpasswd.repo",
            "local/mount.sh:/docker-entrypoint.d/10-mount.sh"
    	]
      }

      volume_mount {
        volume      = "s3fs-passwd"
        destination = "/etc/s3fs-passwd"
        read_only   = true
      }

      resources {
        cpu    = 9000
        memory = 1000
      }

      template {
        destination = "local/htpasswd"
        data = <<EOF
${var.ops_repo_username}:${var.ops_repo_password}:repo user
EOF

      }
      template {
        perms = 755
        destination = "local/mount.sh"
        data = <<EOF
#!/bin/bash

rm -rf /mnt/ops-repo/repo
cp /etc/s3fs-passwd /etc/.s3fs-passwd
chown root:root /etc/.s3fs-passwd
chmod 0600 /etc/.s3fs-passwd
echo 's3fs#${var.ops_bucket} /mnt/ops-repo fuse _netdev,passwd_file=/etc/.s3fs-passwd,url=https://${var.oracle_s3_namespace}.compat.objectstorage.${var.oracle_region}.oraclecloud.com,nomultipart,use_path_request_style,endpoint=${var.oracle_region},allow_other,umask=000 0 0' >> /etc/fstab

mount /mnt/ops-repo
EOF

      }
    }
  }
}