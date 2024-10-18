job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"
  priority = 75

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

  group "cloudprober" {
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

    task "cloudprober" {
      service {
        name = "cloudprober"
        tags = ["int-urlprefix-[[ var "cloudprober_hostname" . ]]/","ip-${attr.unique.network.ip-address}"]
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

apk add curl python3 py3-pip py3-requests
pip install --break-system-packages pystun3
/cloudprober --logtostderr
EOH
        destination = "local/custom_init.sh"
        perms = "755"
      }
      template {
        data = <<EOH
#!/bin/sh

DOMAIN=[[ var "domain" . ]] REGION=[[ var "oracle_region" . ]] /usr/bin/python3 /bin/cloudprober_haproxy_probe.py
EOH
        destination = "local/cloudprober_haproxy_probe.sh"
        perms = "755"
      }
      template {
        data = <<EOH
import requests
import os

url = 'https://' + os.environ['DOMAIN'] + '/about/health'
req = requests.get(url)

if 'x-proxy-region' in req.headers and req.headers['x-proxy-region'] == os.environ['REGION']:
    print('haproxy_region_check_passed 1')
else:
    print('haproxy_region_check_passed 0')
EOH
        destination = "local/cloudprober_haproxy_probe.py"
      }
      template {
        data = <<EOH
import stun, socket

coturn_host = os.environ['COTURN_HOST']
coturn_port = 443
source_host = '0.0.0.0'
source_port = 42000

stun._initialize()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(4)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((source_host, source_port))
results = stun.stun_test(s, coturn_host, coturn_port, source_host, source_port)
s.close()
if results['Resp']:
    print('coturn_stun_check_passed 1')
else:
    print('coturn_stun_check_passed 0')
EOH
        destination = "local/cloudprober_coturn_probe.py"
      }
      template {
        data = <<EOH
#!/bin/sh

if [ -z $1 ]; then
  echo "coturn probe is missing target" 1>&2
  exit 1
fi

COTURN_HOST=$1 /usr/bin/python3 /bin/cloudprober_coturn_probe.py
EOH
        destination = "local/cloudprober_coturn_probe.sh"
        perms = "755"
      }
      config {
        image = "cloudprober/cloudprober:[[ var "cloudprober_version" . ]]"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/cloudprober_haproxy_probe.sh:/bin/cloudprober_haproxy_probe.sh",
          "local/cloudprober_haproxy_probe.py:/bin/cloudprober_haproxy_probe.py",
          "local/cloudprober_coturn_probe.sh:/bin/cloudprober_coturn_probe.sh"
        ]
      }
      resources {
          cpu = 1000
          memory = 256
      }
    }
  }
}
