variable "environment" {
  type = string
}

variable "dc" {
  type = string
}

variable "cloud_provider" {
  type    = string
  default = "oracle"
}

variable "oracle_region" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  priority    = 50

  meta {
    environment    = "${var.environment}"
    cloud_provider = "${var.cloud_provider}"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "ocular" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "10m"
      mode     = "delay"
    }

    network {
      mode = "host"
      port "metrics" {}
    }

    task "ocular" {
      service {
        name = "ocular"
        tags = ["ip-${attr.unique.network.ip-address}"]
        port = "metrics"
        check {
          name     = "alive"
          type     = "http"
          path     = "/metrics"
          port     = "metrics"
          interval = "30s"
          timeout  = "5s"
        }
      }

      driver = "docker"

      config {
        network_mode = "host"
        image        = "python:3.11-slim"
        ports        = ["metrics"]
        command      = "/bin/sh"
        args         = ["-c", "pip install --quiet --no-cache-dir oci && python3 /local/ocular.py"]
        volumes      = ["local/ocular.py:/local/ocular.py"]
      }

      template {
        data = <<PYEOF
#!/usr/bin/env python3
import datetime
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import oci

COMPARTMENT_ID = "${var.compartment_ocid}"
REGION         = "${var.oracle_region}"
NAMESPACE      = "oci_lbaas"
PORT           = int(os.environ.get("NOMAD_HOST_PORT_metrics", "9273"))
STALE_SECS     = 120

METRICS = [
    "AcceptedConnections",
    "ActiveConnections",
    "ActiveSSLConnections",
    "BackendTimeouts",
    "BytesReceived",
    "BytesSent",
    "HttpResponses4xx",
    "HttpResponses5xx",
    "HttpResponses502",
    "HttpResponses504",
    "PeakBandwidth",
    "ResponseTimeHttpHeader",
    "UnHealthyBackendServers",
]

_lock    = threading.Lock()
_samples = []  # list of (prom_line: str, collected_at: float)


def to_snake(name):
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s).lower()


def escape_label(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def make_labels(dims):
    keys = {
        "lb_name":      dims.get("lbName", ""),
        "backend_set":  dims.get("backendSetName", ""),
        "ad":           dims.get("availabilityDomain", ""),
        "lb_component": dims.get("lbComponent", ""),
    }
    parts = [f'{k}="{escape_label(v)}"' for k, v in keys.items() if v]
    return "{" + ",".join(parts) + "}" if parts else ""


def collect():
    try:
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    except Exception as e:
        print(f"instance principal auth failed: {e}", file=sys.stderr)
        return

    client   = oci.monitoring.MonitoringClient({"region": REGION}, signer=signer)
    end_time = datetime.datetime.utcnow()
    start    = end_time - datetime.timedelta(minutes=5)
    now_ts   = time.time()
    new      = []

    for metric in METRICS:
        try:
            resp = client.summarize_metrics_data(
                compartment_id=COMPARTMENT_ID,
                summarize_metrics_data_details=oci.monitoring.models.SummarizeMetricsDataDetails(
                    namespace=NAMESPACE,
                    query=f"{metric}[1m].sum()",
                    start_time=start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    end_time=end_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                ),
            )
        except Exception as e:
            print(f"error querying {metric}: {e}", file=sys.stderr)
            continue

        for item in resp.data:
            if not item.aggregated_datapoints:
                continue
            dp  = item.aggregated_datapoints[-1]
            age = (end_time - dp.timestamp.replace(tzinfo=None)).total_seconds()
            if age > STALE_SECS:
                continue
            labels = make_labels(item.dimensions or {})
            name   = f"oci_lbaas_{to_snake(metric)}"
            new.append((f"{name}{labels} {dp.value}", now_ts))

    with _lock:
        _samples[:] = new


def collector_loop():
    while True:
        try:
            collect()
        except Exception as e:
            print(f"collector error: {e}", file=sys.stderr)
        time.sleep(60)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        cutoff = time.time() - STALE_SECS
        with _lock:
            lines = [line for line, ts in _samples if ts >= cutoff]
        body = ("\n".join(lines) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=collector_loop, daemon=True).start()
    print(f"listening on :{PORT}", file=sys.stderr, flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PYEOF
        destination = "local/ocular.py"
        perms       = "0755"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
