job [[ template "job_name" . ]] {
  [[ template "region" . ]]
  datacenters = [[ var "datacenters" . | toStringList ]]
  type = "service"
  priority = 75

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "15s"
    healthy_deadline  = "3m"
    progress_deadline = "5m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
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

apk add curl python3 py3-requests
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
import sys

url = 'https://' + os.environ['DOMAIN'] + '/about/health'
req = requests.get(url)

if 'x-proxy-region' in req.headers:
  proxy_region = req.headers['x-proxy-region']
  if proxy_region == os.environ['REGION']:
    print('haproxy_region_check_passed{response_region="' + proxy_region + '"} 1')
  else:
    print('haproxy_region_check_passed{response_region="' + proxy_region + '"} 0')
    print('haproxy_region_check hit ' + proxy_region + ' instead of local region ' + os.environ['REGION'], file=sys.stderr)
EOH
        destination = "local/cloudprober_haproxy_probe.py"
      }
      template {
        data = <<EOH
import socket
import os
import binascii
import logging
import random
import socket

log = logging.getLogger("coturn_stun")

def stun_test(sock, host, port, source_ip, source_port):
    BindRequestMsg = '0001'
    BindResponseMsg = '0101'
    MagicCookie = '2112A442'
    def b2a_hexstr(abytes):
        return binascii.b2a_hex(abytes).decode("ascii")

    str_len = '0000'
    #str_len = "%#04d" % 0
    tranid = ''.join(random.choice('0123456789ABCDEF') for i in range(24))
    str_data = ''.join([BindRequestMsg, str_len, MagicCookie, tranid])
    data = binascii.a2b_hex(str_data)

    recieved = False
    count = 3
    while not recieved:
        log.debug("sendto: %s", (host, port))
        try:
            sock.sendto(data, (host, port))
        except socket.gaierror:
            return False
        try:
            buf, addr = sock.recvfrom(2048)
            log.debug("recvfrom: %s", addr)
            recieved = True
        except Exception:
            recieved = False
            if count > 0:
                count -= 1
            else:
                return False
    msgtype = b2a_hexstr(buf[0:2])
    tranid_match = tranid.upper() == b2a_hexstr(buf[8:20]).upper()
    return msgtype == BindResponseMsg and tranid_match

coturn_host = os.environ['COTURN_HOST']
coturn_port = 443
source_host = '0.0.0.0'
source_port = 42000

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(10)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((source_host, source_port))
success = stun_test(s, coturn_host, coturn_port, source_host, source_port)
s.close()
if success:
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
          "local/cloudprober_coturn_probe.sh:/bin/cloudprober_coturn_probe.sh",
          "local/cloudprober_coturn_probe.py:/bin/cloudprober_coturn_probe.py"
        ]
      }
      resources {
          cpu = 1000
          memory = 256
      }
    }
  }
}
