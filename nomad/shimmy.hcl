variable "dc" {
  type = string
}

variable "shimmy_hostname" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "region" {
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

  group "shimmy" {
    count = 1

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    network {
      port "http" {
        to = 8000
      }
    }

    service {
      name = "shimmy"
      tags = ["int-urlprefix-${var.shimmy_hostname}/"]
      port = "http"
      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        port     = "http"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "shimmy" {
      driver = "docker"

      template {
        data = <<EOF
#!/bin/sh
apk add --no-cache py3-pip
pip install --break-system-packages "fastapi[standard]" oci

cd /opt
uvicorn shimmy:app --host 0.0.0.0 --port 8000 --workers 4
EOF
        destination = "local/custom_init.sh"
        perms = "755"
      }

      template {
        data = <<EOF
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel
import oci
import uvicorn
import logging
import sys

compartment_ocid = "${var.compartment_ocid}"
topic_name = "${var.topic_name}"

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('uvicorn.error')
logger.info("shimmy is starting up")

oci_signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
ndpc = oci.ons.NotificationDataPlaneClient(config={'region': '{{ env "meta.cloud_region" }}'}, signer=oci_signer)
ncpc = oci.ons.NotificationControlPlaneClient(config={'region': '{{ env "meta.cloud_region" }}'}, signer=oci_signer)

topics = ncpc.list_topics(compartment_id=compartment_ocid).data
email_topic = next((t for t in topics if t.name == topic_name), None)
if email_topic:
  logger.info(f"found alert email topic {topic_name} in {compartment_ocid}")
  email_topic_id = email_topic.topic_id
else:
  sys.exit(f"failed to find alert email topic {topic_name} in {compartment_ocid}")

class Alert(BaseModel):
  version: str             # alertmanager version
  groupKey: str            # key to id alert group for deduplication
  truncatedAlerts: int     # how many alerts are truncated past max_alerts
  status: str              # <resolved|firing>
  receiver: str            # receiver name
  groupLabels: dict        # labels for the group
  commonLabels: dict       # labels for all alerts
  commonAnnotations: dict  # annotations for all alerts
  externalURL: str         # backlink to alertmanager
  alerts: list             # list of alerts

@app.get("/health")
async def healthcheck():
    return {"healthy": "true"}

@app.post("/alerts")
async def alerts(alert: Alert):
    logger.info(f"Received alert: {alert}")
    send_email(alert)
    return {"message": "Alert received"}

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    exc_str = f'{exc}'.replace('\n', ' ').replace('   ', ' ')
    logger.error(request, exc_str)
    content = {'status_code': 10422, 'message': exc_str, 'data': None}
    return JSONResponse(content=content, status_code=status.HTTP_422_UNPROCESSABLE_ENTITY)

def send_email(alert: Alert):
  if 'alertname' not in alert.commonLabels:
    logger.error('alerts are not grouped by alertname')
    email_title = f"[???] MUNGED ALERTS IN ${var.dc}"
    email_body = f"alerts are not grouped by alertname; something is broken in alertmanager\n\n{alert}"
  elif 'severity' not in alert.commonLabels:
    severity = 'SMOKE'
    for a in alert.alerts:
      if a.labels['severity'] == 'SEVERE':
        severity = 'SEVERE'
        break
      if a.labels['severity'] == 'WARN':
        severity = 'WARN'
    email_title = f"[{severity}] {alert.commonLabels['alertname']} in ${var.dc}"

  email_body = ""
  for a in alert.alerts:
    email_body += f"[{a['status'].upper()}]: {a.labels['alertname']} in {a.labels['datacenter']}: {a.annotations['summary']}\n\n" + \
      f"{a.annotations['description']}\n\n" + \
      f"view the alert in the datacenter's Prometheus: {a.annotations['alert_url']}\n" + \
      f"see the global alert dashboard: {a.annotations['dashboard_url']}\n-=-=-=-=-=-=-\n"

  # TO ADD: runbook URL, any other useful dashboards in grafana
  logger.info("sending an email with\ntitle: {email_title}\nbody: {email_body}")
  message = oci.ons.models.MessageDetails(body=email_body, title=email_title)
  result = ndpc.publish_message(email_topic_id,message)
  logger.info(f"result: {result.data}")

if __name__ == "__main__":
  uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
        destination = "local/shimmy.py"
        perms = "755"
      }

      config {
        image = "python:alpine"
        ports = ["http"]
        entrypoint = ["/bin/custom_init.sh"]
        volumes = [
          "local/custom_init.sh:/bin/custom_init.sh",
          "local/shimmy.py:/opt/shimmy.py"
        ]
      }
    }
  }
}