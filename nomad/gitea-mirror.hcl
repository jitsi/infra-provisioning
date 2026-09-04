variable "dc" {
  type = string
}

variable "gitea_hostname" {
  type = string
}

# Pinned Gitea image. The rooted (non-rootless) image is used because its
# entrypoint runs `gitea web` as the built-in `git` user (uid 1000) and the
# gitea CLI refuses to run as root, so the init task below is also run as
# uid 1000 and everything under /alloc/gitea ends up owned by that user.
variable "image_version" {
  type    = string
  default = "gitea/gitea:1.22"
}

# Small stdlib-only image used by the sync-gate sidecar (seed + /ready server).
variable "gate_image" {
  type    = string
  default = "python:3.12-alpine"
}

# How often Gitea re-pulls each mirror from GitHub.
variable "mirror_interval" {
  type    = string
  default = "10m"
}

# GitHub org the source repos live under, and the Gitea org they are mirrored
# into. Kept identical so boot clones use the same /jitsi/<repo> path.
variable "github_org" {
  type    = string
  default = "jitsi"
}

# Repos that must finish their first sync before the replica is considered
# ready (decision 4). Order does not matter. jitsi-meet is NOT in the default
# set — it is only cloned by boots in us-phoenix-1, so the deploy script adds it
# there (see scripts/deploy-nomad-gitea-mirror.sh).
variable "required_repos" {
  type    = list(string)
  default = ["infra-configuration", "infra-provisioning", "infra-customizations-private"]
}

# Subset of required_repos that must stay private in Gitea and therefore need
# the GitHub token as migrate auth. Everything else is mirrored public/anon.
variable "private_repos" {
  type    = list(string)
  default = ["infra-customizations-private"]
}

# Job name is substituted by scripts/deploy-nomad-gitea-mirror.sh as
# gitea-mirror-<region>. Nomad runs one global region with per-region
# datacenters, so a fixed name would make each region's deploy replace the
# previous region's job.
job "[JOB_NAME]" {
  datacenters = ["${var.dc}"]

  type = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "gitea" {
    count = 2

    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    constraint {
      attribute = "${meta.pool_type}"
      operator  = "set_contains_any"
      value     = "consul,general"
    }

    affinity {
      attribute = "${meta.pool_type}"
      value     = "consul"
      weight    = -100
    }

    affinity {
      attribute = "${meta.pool_type}"
      value     = "general"
      weight    = 100
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "delay"
    }

    # Bridge mode so the three tasks share a network namespace: the sync-gate
    # reaches Gitea over 127.0.0.1:3000, and only the gate's /ready is health
    # checked. No host volume — state lives in the alloc dir and is re-mirrored
    # on reschedule (decision 3).
    network {
      mode = "bridge"
      port "http" {
        to = 3000
      }
      port "health" {
        to = 8080
      }
    }

    # --- init: create the Gitea admin + a scoped seed token before Gitea starts.
    # Runs the gitea CLI against the shared alloc dir (mounted at /alloc in every
    # task). Idempotent: on an in-place restart the admin already exists (|| true)
    # and a fresh uniquely-named token is minted for the gate.
    #
    # Must run as uid 1000 (the image's `git` user), not root: Gitea 1.22 exits
    # fatally when run as root, and anything written as root under /alloc/gitea
    # (app.ini, sqlite db) would be unwritable by the main gitea task, which the
    # image entrypoint drops to `git` via su-exec. Nomad's shared /alloc dir is
    # mode 0777 so uid 1000 can create the tree.
    task "init" {
      driver = "docker"
      user   = "1000:1000"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      vault {
        change_mode = "noop"
      }

      config {
        image      = "${var.image_version}"
        force_pull = false
        entrypoint = ["/bin/sh", "-c"]
        args       = ["/local/init.sh"]
      }

      env {
        GITEA_WORK_DIR                = "/alloc/gitea"
        GITEA_CUSTOM                  = "/alloc/gitea/custom"
        GITEA_APP_INI                 = "/alloc/gitea/custom/conf/app.ini"
        GITEA__database__DB_TYPE      = "sqlite3"
        GITEA__database__PATH         = "/alloc/gitea/data/gitea.db"
        GITEA__repository__ROOT       = "/alloc/gitea/data/repositories"
        GITEA__server__APP_DATA_PATH  = "/alloc/gitea/data"
        GITEA__security__INSTALL_LOCK = "true"
      }

      template {
        destination = "secrets/admin.env"
        env         = true
        change_mode = "noop"
        data        = <<EOF
{{ with secret "secret/default/gitea/admin" -}}
GITEA_ADMIN_USER={{ .Data.data.username }}
GITEA_ADMIN_PASSWORD={{ .Data.data.password }}
GITEA_ADMIN_EMAIL={{ .Data.data.email }}
{{ end -}}
EOF
      }

      template {
        perms       = 755
        destination = "local/init.sh"
        data        = <<EOF
#!/bin/sh
set -e

mkdir -p /alloc/gitea/custom/conf /alloc/gitea/data /alloc/gitea/data/repositories /alloc/gitea-seed

# Render app.ini from the GITEA__* env to the shared path so the CLI here and
# the main gitea task agree on the DB/repo locations.
if [ -x /usr/local/bin/environment-to-ini ]; then
  environment-to-ini -o "$GITEA_APP_INI"
fi

CONF="$GITEA_APP_INI"

# Initialise / migrate the sqlite schema (safe to re-run).
gitea -c "$CONF" migrate

# Create the site admin (first user is a site admin). Idempotent across restarts.
gitea -c "$CONF" admin user create \
  --admin \
  --username "$GITEA_ADMIN_USER" \
  --password "$GITEA_ADMIN_PASSWORD" \
  --email "$GITEA_ADMIN_EMAIL" \
  --must-change-password=false || true

# Mint a fresh, uniquely-named token for the sync-gate to seed/inspect mirrors.
TOKEN=$(gitea -c "$CONF" admin user generate-access-token \
  --username "$GITEA_ADMIN_USER" \
  --token-name "seed-$(date +%s)" \
  --scopes "write:repository,write:organization,write:admin,read:user" \
  --raw)
printf '%s' "$TOKEN" > /alloc/gitea-seed/token
chmod 600 /alloc/gitea-seed/token
echo "init: admin ensured and seed token written"
EOF
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }

    # --- gitea: the mirror server itself. Serves git over HTTP through Fabio.
    task "gitea" {
      driver         = "docker"
      shutdown_delay = "10s"

      config {
        image      = "${var.image_version}"
        force_pull = false
        ports      = ["http"]
      }

      env {
        GITEA_WORK_DIR                       = "/alloc/gitea"
        GITEA_CUSTOM                         = "/alloc/gitea/custom"
        GITEA_APP_INI                        = "/alloc/gitea/custom/conf/app.ini"
        GITEA__database__DB_TYPE             = "sqlite3"
        GITEA__database__PATH                = "/alloc/gitea/data/gitea.db"
        GITEA__repository__ROOT              = "/alloc/gitea/data/repositories"
        GITEA__server__APP_DATA_PATH         = "/alloc/gitea/data"
        GITEA__server__HTTP_PORT             = "3000"
        GITEA__server__ROOT_URL              = "https://${var.gitea_hostname}/"
        GITEA__server__DOMAIN                = "${var.gitea_hostname}"
        GITEA__server__DISABLE_SSH           = "true"
        GITEA__security__INSTALL_LOCK        = "true"
        GITEA__service__DISABLE_REGISTRATION = "true"
        GITEA__service__REQUIRE_SIGNIN_VIEW  = "false"
        GITEA__mirror__ENABLED               = "true"
        # Must include *.github.com: the `service: github` migrator talks to
        # api.github.com before cloning, and a bare "github.com" entry rejects
        # that with "migration can only call allowed HTTP servers".
        GITEA__migrations__ALLOWED_DOMAINS   = "github.com,*.github.com"
        GITEA__log__LEVEL                    = "Info"
      }

      service {
        name = "gitea-mirror"
        tags = ["int-urlprefix-${var.gitea_hostname}/"]
        port = "http"

        # Health is the sync-gate's /ready, NOT Gitea's own liveness: a replica
        # stays out of Fabio until every required repo has finished first sync
        # (decision 4). limit = 0 so the gate returning 503 during initial sync
        # never restarts the task.
        check {
          name     = "ready"
          type     = "http"
          port     = "health"
          path     = "/ready"
          interval = "15s"
          timeout  = "5s"

          check_restart {
            limit = 0
          }
        }
      }

      resources {
        cpu    = 2000
        memory = 1024
      }
    }

    # --- sync-gate: poststart sidecar. Seeds the mirrors (idempotent) then
    # serves /ready — 503 until all required repos report "empty": false.
    task "sync-gate" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      vault {
        change_mode = "noop"
      }

      config {
        image      = "${var.gate_image}"
        force_pull = false
        ports      = ["health"]
        entrypoint = ["/bin/sh", "-c"]
        args       = ["python3 /local/sync-gate.py"]
      }

      env {
        GITEA_URL             = "http://127.0.0.1:3000"
        GITEA_ORG             = "${var.github_org}"
        GITHUB_ORG            = "${var.github_org}"
        GITEA_REQUIRED_REPOS  = "${join(" ", var.required_repos)}"
        GITEA_PRIVATE_REPOS   = "${join(" ", var.private_repos)}"
        GITEA_MIRROR_INTERVAL = "${var.mirror_interval}"
        GATE_PORT             = "8080"
      }

      template {
        destination = "secrets/github.env"
        env         = true
        change_mode = "noop"
        data        = <<EOF
{{ with secret "secret/default/gitea/github" -}}
GITHUB_TOKEN={{ .Data.data.token }}
{{ end -}}
EOF
      }

      template {
        perms       = 755
        destination = "local/sync-gate.py"
        data        = <<EOF
#!/usr/bin/env python3
"""Sync-gate for the Gitea regional mirror.

1. Waits for Gitea, using the seed token written by the init task.
2. Ensures the target org exists and each required repo is migrated as a pull
   mirror from GitHub (idempotent create-if-absent).
3. Serves /ready on GATE_PORT: 503 until every required repo reports
   "empty": false (first sync done), then 200.
"""
import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

GITEA_URL = os.environ["GITEA_URL"].rstrip("/")
GITEA_ORG = os.environ["GITEA_ORG"]
GITHUB_ORG = os.environ["GITHUB_ORG"]
REQUIRED = os.environ.get("GITEA_REQUIRED_REPOS", "").split()
PRIVATE = set(os.environ.get("GITEA_PRIVATE_REPOS", "").split())
INTERVAL = os.environ.get("GITEA_MIRROR_INTERVAL", "10m")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GATE_PORT = int(os.environ.get("GATE_PORT", "8080"))
TOKEN_FILE = "/alloc/gitea-seed/token"

_ready = threading.Event()


def read_token():
    for _ in range(120):
        try:
            with open(TOKEN_FILE) as fh:
                tok = fh.read().strip()
            if tok:
                return tok
        except OSError:
            pass
        time.sleep(2)
    raise SystemExit("sync-gate: seed token never appeared at %s" % TOKEN_FILE)


def api(method, path, token, body=None, expect=(200, 201)):
    url = GITEA_URL + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "token " + token)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = resp.read()
            return resp.status, (json.loads(payload) if payload else {})
    except urllib.error.HTTPError as e:
        payload = e.read()
        try:
            parsed = json.loads(payload) if payload else {}
        except ValueError:
            parsed = {"raw": payload.decode("utf-8", "replace")}
        return e.code, parsed
    except urllib.error.URLError:
        return 0, {}


def wait_for_gitea(token):
    while True:
        status, _ = api("GET", "/api/v1/version", token)
        if status == 200:
            print("sync-gate: gitea is up", flush=True)
            return
        time.sleep(3)


def ensure_org(token):
    status, _ = api("GET", "/api/v1/orgs/%s" % GITEA_ORG, token)
    if status == 200:
        return
    status, body = api(
        "POST", "/api/v1/orgs", token,
        {"username": GITEA_ORG, "visibility": "public"},
    )
    if status not in (201, 422):  # 422 => already exists (race)
        print("sync-gate: WARN could not create org %s: %s %s" % (GITEA_ORG, status, body), flush=True)


def ensure_mirror(token, repo):
    status, _ = api("GET", "/api/v1/repos/%s/%s" % (GITEA_ORG, repo), token)
    if status == 200:
        return
    private = repo in PRIVATE
    body = {
        "clone_addr": "https://github.com/%s/%s.git" % (GITHUB_ORG, repo),
        "repo_owner": GITEA_ORG,
        "repo_name": repo,
        "mirror": True,
        "mirror_interval": INTERVAL,
        "private": private,
        "service": "github",
    }
    # Sync over HTTPS + token (never the SSH deploy key) so the mirror's own
    # sync path is immune to the deploy-key failure class that caused JIT-16092.
    if GITHUB_TOKEN:
        body["auth_token"] = GITHUB_TOKEN
    status, resp = api("POST", "/api/v1/repos/migrate", token, body)
    if status in (201, 409):
        print("sync-gate: migrate %s -> %s" % (repo, status), flush=True)
    else:
        print("sync-gate: WARN migrate %s failed: %s %s" % (repo, status, resp), flush=True)


def repo_synced(token, repo):
    status, body = api("GET", "/api/v1/repos/%s/%s" % (GITEA_ORG, repo), token)
    return status == 200 and body.get("empty") is False


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/ready"):
            code = 200 if _ready.is_set() else 503
        else:
            code = 200
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n" if code == 200 else b"syncing\n")

    def log_message(self, *args):
        pass


def serve():
    HTTPServer(("0.0.0.0", GATE_PORT), Handler).serve_forever()


def main():
    # Serve /ready (503) immediately so the health check has an endpoint while
    # the mirrors are still being seeded.
    threading.Thread(target=serve, daemon=True).start()

    token = read_token()
    wait_for_gitea(token)
    ensure_org(token)
    for repo in REQUIRED:
        ensure_mirror(token, repo)

    while True:
        if all(repo_synced(token, r) for r in REQUIRED):
            if not _ready.is_set():
                print("sync-gate: all repos synced, ready", flush=True)
            _ready.set()
        else:
            _ready.clear()
        time.sleep(10)


if __name__ == "__main__":
    main()
EOF
      }

      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
