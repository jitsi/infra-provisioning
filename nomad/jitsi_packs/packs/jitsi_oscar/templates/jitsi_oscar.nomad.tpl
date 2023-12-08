job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
  }

  reschedule {
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "1h"
    unlimited      = true
  }

  // must have linux for network mode
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  meta {
    cloudprober_version = "[[ var "cloudprober_version" . ]]"
  }

  group "synthetics" {
    constraint {
      attribute  = "${meta.pool_type}"
      value     = "[[ var "pool_type" . ]]"
    }

    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 9313 
      }
    }

    task "ingress-cloudprober" {
      service {
        name = "oscar"
        tags = ["int-urlprefix-[[ var "oscar_hostname" . ]]/","ip-${attr.unique.network.ip-address}"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      template {
          data = <<EOH
[[ template "cloudprober-config" . ]]
EOH
          destination = "local/cloudprober.cfg"
      }
      template {
        data = <<EOH
#!bin/sh

apk add python3 curl
/usr/bin/python3 -m ensurepip --default-pip
/usr/bin/python3 -m pip install requests
/cloudprober --logtostderr
EOH
        destination = "local/custom_init.sh"
        perms = "755"
      }
      template {
        data = <<EOH
#!/bin/sh

DOMAIN=[[ var "domain" . ]] REGION=[[ var "oracle_region" . ]] /usr/bin/python3 /bin/oscar_haproxy_probe.py
EOH
        destination = "local/oscar_haproxy_probe.sh"
        perms = "755"
      }
      template {
        data = <<EOH
import requests
import os

url = 'https://' + os.environ['DOMAIN'] + "/about/health"
req = requests.get(url)

if req.headers['x-proxy-region'] == os.environ['REGION']:
    print("haproxy_region_check_passed 1")
else:
    print("haproxy_region_check_passed 0")
EOH
        destination = "local/oscar_haproxy_probe.py"
      }
      template {
        data = <<EOH
#!/bin/sh

if [ -z $1 ]; then
  echo "coturn probe is missing target"
  exit 1
fi

OUT=$(curl -s https://[[ var "environment" . ]]-turnrelay-oracle.jitsi.net/ --resolve "[[ var "environment" . ]]-turnrelay-oracle.jitsi.net:443:$1")
if [ $? -ne 52 ]; then
  echo "coturn probe failed: CODE $1 OUT $OUT" 1>&2
  echo "coturn_check_passed 0"
  exit 1
fi
echo "coturn_check_passed 1"
EOH
        destination = "local/oscar_coturn_probe.sh"
        perms = "755"
      }
      config {
        image = "cloudprober/cloudprober:[[ var "cloudprober_version" . ]]"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/oscar_haproxy_probe.sh:/bin/oscar_haproxy_probe.sh",
          "local/oscar_haproxy_probe.py:/bin/oscar_haproxy_probe.py",
          "local/oscar_coturn_probe.sh:/bin/oscar_coturn_probe.sh"
        ]
      }
      resources {
          cpu = 2000
          memory = 256
      }
    }
  }
}
