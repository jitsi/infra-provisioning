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

  # The health check is the sync-gate's /ready, which deliberately stays 503
  # until every required repo has finished its first clone (decision 4). In
  # us-phoenix-1 that includes jitsi-meet, so a cold replica legitimately takes
  # far longer than Nomad's default 5m healthy_deadline, which would fail the
  # rollout while the mirror is still syncing normally. auto_revert keeps the
  # previous, already-synced version serving when a new one never gets there.
  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "20m"
    progress_deadline = "30m"
    auto_revert       = true
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
        # Retry pacing for the mirror seed (see local/sync-gate.py).
        # GATE_STALL_TIMEOUT is how long an empty repo may sit before it is
        # treated as a dead stub and re-migrated, so it must comfortably exceed
        # the first-clone time of the largest mirrored repo.
        GATE_MIGRATE_TIMEOUT  = "1800"
        GATE_STALL_TIMEOUT    = "900"
        GATE_RETRY_BACKOFF    = "60"
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
   mirror from GitHub, retrying until that succeeds.
3. Serves /ready on GATE_PORT: 503 until every required repo reports
   "empty": false (first sync done), then 200.

Retrying a migrate is not just a matter of calling it again. A migrate Gitea
rejects still leaves a repo row behind (empty, no mirror interval) and that
stub answers GET with 200 for good, so it has to be deleted first -- a second
migrate over an existing repo returns 409. A migration that is still running
looks exactly like that stub, and it keeps running even when our request times
out client-side, so deleting on sight would destroy healthy in-flight clones.
A stub is therefore only removed once the migrate has failed outright, or once
it has sat there past GATE_STALL_TIMEOUT without becoming non-empty.
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

# How long to let a migrate request run before giving up on the answer. Gitea
# migrates synchronously, so a big repo can hold the connection for minutes.
MIGRATE_TIMEOUT = int(os.environ.get("GATE_MIGRATE_TIMEOUT", "1800"))
# How long an empty repo may sit there before it is treated as a dead stub.
# Must comfortably exceed the first-clone time of the largest mirrored repo.
STALL_TIMEOUT = int(os.environ.get("GATE_STALL_TIMEOUT", "900"))
# Minimum gap between migrate attempts for one repo, so a GitHub outage is not
# hammered.
RETRY_BACKOFF = int(os.environ.get("GATE_RETRY_BACKOFF", "60"))
POLL_INTERVAL = int(os.environ.get("GATE_POLL_INTERVAL", "10"))

_ready = threading.Event()


class RepoState(object):
    """What our last migrate attempt for one repo did.

    outcome is None before the first attempt, "failed" when Gitea answered with
    an error (so nothing is running and any stub is garbage), or "unknown" when
    the attempt may still be progressing inside Gitea.
    """

    def __init__(self):
        self.attempted_at = None
        self.outcome = None


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


def api(method, path, token, body=None, timeout=30):
    url = GITEA_URL + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "token " + token)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
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
    except OSError:
        # Socket timeout on a long migrate: Gitea carries on regardless.
        return 0, {}


def wait_for_gitea(token):
    while True:
        status, _ = api("GET", "/api/v1/version", token)
        if status == 200:
            print("sync-gate: gitea is up", flush=True)
            return
        time.sleep(3)


def ensure_org(token):
    """True once the org exists. Retried by the caller until it does."""
    status, _ = api("GET", "/api/v1/orgs/%s" % GITEA_ORG, token)
    if status == 200:
        return True
    status, body = api(
        "POST", "/api/v1/orgs", token,
        {"username": GITEA_ORG, "visibility": "public"},
    )
    if status in (201, 422):  # 422 => already exists (race)
        return True
    print("sync-gate: WARN could not create org %s: %s %s" % (GITEA_ORG, status, body), flush=True)
    return False


def start_migrate(token, repo, st):
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
    # Only the private repos get the token: Gitea sends it to api.github.com for
    # every migrate it is attached to, so putting it on public repos too means a
    # single bad or expired PAT fails every mirror, including the public ones the
    # boot path depends on most.
    if private and GITHUB_TOKEN:
        body["auth_token"] = GITHUB_TOKEN
    st.attempted_at = time.monotonic()
    status, resp = api("POST", "/api/v1/repos/migrate", token, body, timeout=MIGRATE_TIMEOUT)
    if status in (201, 409):
        st.outcome = "unknown"
        print("sync-gate: migrate %s -> %s" % (repo, status), flush=True)
    elif status == 0:
        # No answer: the clone is most likely still running inside Gitea, so
        # this is explicitly not a failure. The stall timer covers it.
        st.outcome = "unknown"
        print("sync-gate: migrate %s: no answer yet, leaving it to run" % repo, flush=True)
    else:
        st.outcome = "failed"
        print("sync-gate: WARN migrate %s failed: %s %s" % (repo, status, resp), flush=True)


def drop_stub(token, repo, st, why):
    """Delete an empty repo so the next pass can migrate it again."""
    status, resp = api("DELETE", "/api/v1/repos/%s/%s" % (GITEA_ORG, repo), token)
    if status in (204, 404):
        # attempted_at is deliberately left alone: it paces the retry.
        st.outcome = None
        print("sync-gate: removed %s stub (%s), will migrate again" % (repo, why), flush=True)
    else:
        print("sync-gate: WARN could not remove %s stub: %s %s" % (repo, status, resp), flush=True)


def reconcile(token, repo, st):
    """Drive one repo towards being mirrored. True once its first sync is done."""
    status, body = api("GET", "/api/v1/repos/%s/%s" % (GITEA_ORG, repo), token)

    if status == 200 and body.get("empty") is False:
        st.outcome = None
        return True

    now = time.monotonic()

    if status == 404:
        if st.attempted_at is None or now - st.attempted_at >= RETRY_BACKOFF:
            start_migrate(token, repo, st)
        return False

    if status == 200:
        # The repo exists but is still empty: either a clone in flight or a
        # stub left behind by one that failed.
        if st.attempted_at is None:
            # Left by an earlier gate process. Time it out rather than delete
            # it, in case Gitea is still working on it.
            st.attempted_at = now
            st.outcome = "unknown"
        elif st.outcome == "failed":
            drop_stub(token, repo, st, "migrate failed")
        elif now - st.attempted_at >= STALL_TIMEOUT:
            drop_stub(token, repo, st, "no progress in %ss" % STALL_TIMEOUT)
        return False

    # Gitea restarting or a transient error: just look again next pass.
    return False


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

    state = dict((repo, RepoState()) for repo in REQUIRED)
    org_ok = False

    while True:
        if not org_ok:
            org_ok = ensure_org(token)
        # Not all(...): every repo must be reconciled on every pass, so this
        # must not short-circuit on the first one that is not ready yet.
        done = [reconcile(token, repo, state[repo]) for repo in REQUIRED] if org_ok else []
        if org_ok and all(done):
            if not _ready.is_set():
                print("sync-gate: all repos synced, ready", flush=True)
            _ready.set()
        else:
            _ready.clear()
        time.sleep(POLL_INTERVAL)


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
