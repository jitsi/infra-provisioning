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
CYCLE_SECS     = 60
STALE_SECS     = 120

# OCI Monitoring rate-limits summarize_metrics_data over a short window, and
# a burst of back-to-back queries gets its last few rejected with 429. Space
# the queries out across the cycle instead: 15 queries at 3s fit in 60s.
QUERY_SPACING_SECS = 3

# Bounded retries for throttling and transient errors. The SDK default retries
# up to 8 times over 10 minutes, which would stall the whole collection cycle.
RETRY_STRATEGY = oci.retry.RetryStrategyBuilder(
    max_attempts=3,
    total_elapsed_time_seconds=15,
    retry_base_sleep_time_seconds=2,
    retry_max_wait_between_calls_seconds=8,
    backoff_type=oci.retry.BACKOFF_FULL_JITTER_EQUAL_ON_THROTTLE_VALUE,
).get_retry_strategy()

# One entry per OCI monitoring namespace.
#
# interval_secs is how often the namespace is queried. A metric whose query
# fails keeps its last good samples and is retried on the next cycle.
# Samples are served until interval_secs + STALE_SECS after they were
# collected, so one failed query does not drop a series.
#
# lookback_min and max_age_secs are per namespace because posting cadence
# differs. oci_lbaas posts about every minute. oci_instancepools posts sparsely
# and irregularly (2-8 minutes between points, varying per pool), so the short
# lookback and 120s staleness used for lbaas would silently drop most pools.
#
# The OCI "region" and "resourceId" dimensions are deliberately not mapped:
# telegraf already applies a region global tag, and resourceId is high
# cardinality without adding anything the display name does not.
#
# active_pools_only drops series whose resourceId is not a live instance pool.
# OCI keeps publishing oci_instancepools metrics for a pool after it is
# stopped or terminated, which otherwise shows a dead pool as a live one
# short of its configured size.
SOURCES = [
    {
        "namespace":    "oci_lbaas",
        "prefix":       "oci_lbaas",
        "aggregation":  "sum",
        "interval_secs": 60,
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
        # OCI posts these only every few minutes (see above), so querying
        # every minute adds load and no data.
        "interval_secs": 300,
        "lookback_min": 20,
        "max_age_secs": 900,
        "active_pools_only": True,
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

SERVE_SECS = {s["namespace"]: s["interval_secs"] + STALE_SECS for s in SOURCES}

# A pool in any other state (RUNNING, SCALING during a rotation, PROVISIONING,
# STARTING) is live and keeps its series.
INACTIVE_POOL_STATES = {"STOPPING", "STOPPED", "TERMINATING", "TERMINATED"}

_lock     = threading.Lock()
_samples  = {}    # (namespace, metric) -> (prom_lines: list[str], collected_at: float)
_last_ok  = {}    # (namespace, metric) -> time of the last successful query
_pool_ids = None  # last successful active_pool_ids() result

try:
    _signer       = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    _client       = oci.monitoring.MonitoringClient(
        {"region": REGION}, signer=_signer, retry_strategy=RETRY_STRATEGY)
    _compute_mgmt = oci.core.ComputeManagementClient(
        {"region": REGION}, signer=_signer, retry_strategy=RETRY_STRATEGY)
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


def active_pool_ids():
    """OCIDs of the compartment's live instance pools. If the list call fails,
    the last successful result, or None if there has not been one. None means
    keep every series: an OCI API error must not make every pool vanish from
    the metrics."""
    global _pool_ids
    try:
        pools = oci.pagination.list_call_get_all_results(
            _compute_mgmt.list_instance_pools,
            compartment_id=COMPARTMENT_ID,
        ).data
    except Exception as e:
        print(f"error listing instance pools: {e}", file=sys.stderr)
        return _pool_ids
    _pool_ids = {p.id for p in pools if p.lifecycle_state not in INACTIVE_POOL_STATES}
    return _pool_ids


def collect():
    cycle_ts = time.time()
    queried  = 0

    for source in SOURCES:
        namespace = source["namespace"]
        # Half a cycle of slack so timer jitter cannot push a due metric to
        # the cycle after.
        due = [
            metric for metric in source["metrics"]
            if cycle_ts - _last_ok.get((namespace, metric), 0) >= source["interval_secs"] - CYCLE_SECS / 2
        ]
        if not due:
            continue
        pool_ids = active_pool_ids() if source.get("active_pools_only") else None
        for metric in due:
            if queried:
                time.sleep(QUERY_SPACING_SECS)
            queried += 1
            end_time = datetime.datetime.utcnow()
            start    = end_time - datetime.timedelta(minutes=source["lookback_min"])
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
                # Leave the metric's previous samples in place; it is still
                # due, so the next cycle retries it.
                print(f"error querying {namespace} {metric}: {e}", file=sys.stderr)
                continue

            lines = []
            for item in resp.data:
                if not item.aggregated_datapoints:
                    continue
                if pool_ids is not None and (item.dimensions or {}).get("resourceId") not in pool_ids:
                    continue
                dp  = max(item.aggregated_datapoints, key=lambda d: d.timestamp)
                age = (end_time - dp.timestamp.replace(tzinfo=None)).total_seconds()
                if age > source["max_age_secs"]:
                    continue
                labels = make_labels(item.dimensions or {}, source["labels"])
                name   = f"{source['prefix']}_{to_snake(metric)}"
                lines.append(f"{name}{labels} {dp.value}")

            with _lock:
                _samples[(namespace, metric)] = (lines, time.time())
            _last_ok[(namespace, metric)] = cycle_ts


def collector_loop():
    while True:
        started = time.monotonic()
        try:
            collect()
        except Exception as e:
            print(f"collector error: {e}", file=sys.stderr)
        time.sleep(max(0, CYCLE_SECS - (time.monotonic() - started)))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        now = time.time()
        with _lock:
            lines = [
                line
                for (namespace, _), (prom_lines, collected_at) in _samples.items()
                if now - collected_at <= SERVE_SECS[namespace]
                for line in prom_lines
            ]
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
