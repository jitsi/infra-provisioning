    task "ingress-cloudprober" {
      service {
        name = "oscar"
        tags = ["int-urlprefix-${var.oscar_hostname}/","ip-${attr.unique.network.ip-address}"]
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
# probes site ingress health from this datacenter
probe {
  name: "site"
  type: HTTP
  targets {
    host_names: "${var.domain}"
  }
  interval_msec: 5000
  timeout_msec: 2000
}
# probe to validate that the ingress haproxy reached is in the local datacenter
probe {
  name: "haproxy_region"
  type: EXTERNAL
  targets {
    host_names: "${var.domain}"
  }
  external_probe {
    mode: ONCE 
    command: "/bin/oscar_haproxy_probe.sh"
  }
  interval_msec: 5000
  timeout_msec: 2000
}
# probes autoscaler health in the local datacenter
probe {
  name: "autoscaler"
  type: HTTP
  targets {
    host_names: "${var.environment}-${var.region}-autoscaler.${var.top_level_domain}"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/health?deep=true"
  }
  interval_msec: 60000
  timeout_msec: 2000
}
# probes wavefront-proxy health in the local datacenter
probe {
  name: "wfproxy"
  type: HTTP
  targets {
    host_names: "${var.environment}-${var.region}-wfproxy.${var.top_level_domain}"
  }
  http_probe {
    protocol: HTTPS
    relative_url: "/status"
  }
  interval_msec: 60000
  timeout_msec: 2000
}
# probes coturn health in the local datacenter using public IP
probe {
  name: "coturn"
  type: EXTERNAL
  targets {
    host_names: "{{ range $index, $service := service "coturn"}}{{ if gt $index 0 }},{{ end }}{{ .ServiceMeta.public_ip }}{{ end }}"
  }
  external_probe {
    mode: ONCE 
    command: "/bin/oscar_coturn_probe.sh @target@"
  }
  interval_msec: 60000
  timeout_msec: 2000
}
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

DOMAIN=${var.domain} REGION=${var.region} /usr/bin/python3 /bin/oscar_haproxy_probe.py
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

curl -s https://${var.environment}-turnrelay-oracle.jitsi.net/ --resolve "${var.environment}-turnrelay-oracle.jitsi.net:443:$1"
if [ $? -ne 52 ]; then
  echo "coturn_check_passed 0"
  exit 1
fi
echo "coturn_check_passed 1"
EOH
        destination = "local/oscar_coturn_probe.sh"
        perms = "755"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
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
