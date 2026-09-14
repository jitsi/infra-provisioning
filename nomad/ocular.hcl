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

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

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
      shutdown_delay = "5s"
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
PORT           = int(os.environ.get("NOMAD_HOST_PORT_metrics", "9273"))
STALE_SECS     = 120

# One entry per OCI monitoring namespace.
#
# lookback_min and max_age_secs are per namespace because posting cadence
# differs. oci_lbaas posts about every minute. oci_instancepools posts sparsely
# and irregularly (2-8 minutes between points, varying per pool), so the short
# lookback and 120s staleness used for lbaas would silently drop most pools.
#
# The OCI "region" and "resourceId" dimensions are deliberately not mapped:
# telegraf already applies a region global tag, and resourceId is high
# cardinality without adding anything the display name does not.
SOURCES = [
    {
        "namespace":    "oci_lbaas",
        "prefix":       "oci_lbaas",
        "aggregation":  "sum",
        "lookback_min": 5,
        "max_age_secs": 120,
        "labels": {
            "lb_name":      "lbName",
            "backend_set":  "backendSetName",
            "ad":           "availabilityDomain",
            "lb_component": "lbComponent",
        },
        "metrics": [
            "AcceptedConnections",
            "ActiveConnections",
            "ActiveSSLConnections",
            "BackendTimeouts",
            "HttpRequests",
            "HttpResponses2xx",
            "HttpResponses4xx",
            "HttpResponses5xx",
            "PeakBandwidth",
            "ResponseTimeHttpHeader",
            "UnHealthyBackendServers",
        ],
    },
    {
        "namespace":    "oci_instancepools",
        "prefix":       "oci_instancepools",
        "aggregation":  "max",
        "lookback_min": 20,
        "max_age_secs": 900,
        "labels": {
            "pool": "DisplayName",
            "ad":   "AvailabilityDomain",
            "fd":   "FaultDomain",
        },
        "metrics": [
            "InstancePoolSize",
            "RunningInstances",
            "ProvisioningInstances",
            "TerminatedInstances",
        ],
    },
]

_lock    = threading.Lock()
_samples = []  # list of (prom_line: str, collected_at: float)

try:
    _signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    _client = oci.monitoring.MonitoringClient({"region": REGION}, signer=_signer)
except Exception as e:
    print(f"init failed: {e}", file=sys.stderr)
    sys.exit(1)


def to_snake(name):
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s).lower()


def escape_label(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def make_labels(dims, label_map):
    parts = [
        f'{label}="{escape_label(dims.get(dim))}"'
        for label, dim in label_map.items()
        if dims.get(dim)
    ]
    return "{" + ",".join(parts) + "}" if parts else ""


def collect():
    end_time = datetime.datetime.utcnow()
    now_ts   = time.time()
    new      = []

    for source in SOURCES:
        start = end_time - datetime.timedelta(minutes=source["lookback_min"])
        for metric in source["metrics"]:
            try:
                resp = _client.summarize_metrics_data(
                    compartment_id=COMPARTMENT_ID,
                    summarize_metrics_data_details=oci.monitoring.models.SummarizeMetricsDataDetails(
                        namespace=source["namespace"],
                        query=f"{metric}[1m].{source['aggregation']}()",
                        start_time=start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        end_time=end_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    ),
                )
            except Exception as e:
                print(f"error querying {source['namespace']} {metric}: {e}", file=sys.stderr)
                continue

            for item in resp.data:
                if not item.aggregated_datapoints:
                    continue
                dp  = max(item.aggregated_datapoints, key=lambda d: d.timestamp)
                age = (end_time - dp.timestamp.replace(tzinfo=None)).total_seconds()
                if age > source["max_age_secs"]:
                    continue
                labels = make_labels(item.dimensions or {}, source["labels"])
                name   = f"{source['prefix']}_{to_snake(metric)}"
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
        memory = 768
      }
    }
  }
}
