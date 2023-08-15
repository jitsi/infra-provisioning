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
    command: "/bin/oscar_probe.sh"
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
EOH
          destination = "local/cloudprober.cfg"
      }
      template {
        data = <<EOH
#!bin/sh

apk add python3
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

DOMAIN=${var.domain} REGION=${var.region} /usr/bin/python3 /bin/oscar_probe.py
EOH
        destination = "local/oscar_probe.sh"
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
        destination = "local/oscar_probe.py"
      }
      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/cloudprober.cfg:/etc/cloudprober.cfg",
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/oscar_probe.sh:/bin/oscar_probe.sh",
          "local/oscar_probe.py:/bin/oscar_probe.py"
        ]
      }
      resources {
          cpu = 2000
          memory = 256
      }
    }
  }
}
