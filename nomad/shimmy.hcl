variable "dc" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "default_region" {
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

    network {
      port "http" {
        to = 8000
      }
    }

    service {
      name = "shimmy"
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
pip install --break-system-packages "fastapi[standard] oci"

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

compartment_ocid = "${var.compartment_ocid}"
topic_name = "${var.topic_name}"

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('uvicorn.error')
logger.info("shimmy is starting up")

signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
ndpc = oci.ons.NotificationDataPlaneClient(config={'region': '${var.default_region}'}, signer=signer)

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

def send_email(alert: Alert):
  email_title = f"{alert.commonLabels['alertname']} ALERT [{alert.status.upper()}]: {alert.commonAnnotations['summary']}"
  email_body = \
    f"{alert.commonLabels['alertname']} from {alert.commonLabels['datacenter']}.\n\n" + \
    f"{alert.commonAnnotations['description']} For more information, see the following:\n\n" + \
    f"view the alert in the datacenter's Prometheus: {alert.commonAnnotations['alert_url']}\n" + \
    f"see the global alert dashboard: {alert.commonAnnotations['dashboard_url']}"
  # TO ADD: runbook URL, any other useful dashboards in grafana
  logger.debug("sending an email with\ntitle: {email_title}\nbody: {email_body}")
  message = oci.ons.models.MessageDetails(body=email_body, title=email_title)
  result = ndpc.publish_message('ocid1.onstopic.oc1.phx.amaaaaaas3fd7mqaf25unw5ngr3kginpfix4akmtfzefnyqhh5ks4mhqsubq',message)

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