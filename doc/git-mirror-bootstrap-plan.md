# Plan: Local-DC Git Mirror (Gitea) + Vault OCI-Auth Bootstrap Credentials

Status: PROPOSED (not yet implemented)
Tracking: JIT-XXXXX (ticket TBD)
Author: generated 2026-07-21

## Motivation

On 2026-07-21 a GitHub incident — *"intermittent SSH authentication failures
affecting connections that use deploy keys"* (opened 11:04 UTC) — caused fresh
`prod-8x8` JVB instances to fail provisioning. The failure was diagnosed from
the boot dump `prod-8x8-jvb-66-97-202-2026-07-21-1103--dump.tar.gz`:

- The instance (`prod-8x8-uk-london-1-local-6869-jvbcustomgroup-...`) was a
  fresh boot; JVB never started (empty PID, no `jvb.service` in syslog, no
  resource pressure).
- `postinstall-jvb-oracle.sh` ran the provisioning stage, which retried 10x
  and failed every time at `checkout_repos`:

  ```
  Cloning into '/tmp/bootstrap/infra-configuration'...
  git@github.com: Permission denied (publickey).
  ```

- The SSH deploy key (`id_rsa_jitsi_deployment`, fetched from
  `jvb-bucket-prod-8x8`) downloaded fine and was valid — GitHub simply rejected
  deploy-key auth for the duration of the incident.
- After exhausting retries the bootstrap dumped and self-terminated.

**Root cause: the VM boot path has a hard dependency on GitHub SSH deploy-key
authentication.** This affects *every* VM role that clones the infra repos at
boot (JVB, jibri, jigasi, coturn, haproxy, …), not just JVB. Any GitHub outage
that touches SSH/deploy-keys stops the entire fleet from launching new capacity.

### Why the existing mitigations don't cover this

- **`GIT_ALTERNATE_OBJECT_DIRECTORIES` / `/opt/jitsi/bootstrap` object cache**
  (main, PR #900): only a git *object cache*. Even when populated, `git clone`
  still authenticates to the SSH remote — it does not remove the GitHub
  dependency.
- **`bootstrap-repos` role** (infra-configuration PR #207): a build-time bake of
  the repos into `/opt/jitsi/bootstrap`, plus an offline "use instead of clone"
  consumer path. It was **backed out** in PR #211 ("fix: backout bootstrap repos
  for now") and is commented out in all build playbooks. Confirmed absent on the
  live `stage-8x8-jvb-72-67-50` box (`/opt/jitsi/bootstrap` does not exist). Even
  the offline consumer variant ran `git pull` under `set -e`, so a GitHub outage
  would still abort boot.
- **`ops-git`** (`docker/ops-git`): a prototype git-over-SSH mirror
  (`aaronkvanmeerten/ops-git:0.0.1`, personal image) that is **not deployed
  anywhere** (no Nomad job, no Terraform).

## Goal

Remove GitHub availability from the VM boot path by:

1. **Mirroring the required repos inside each OCI region** so boots clone from a
   local, always-available mirror instead of GitHub.
2. **Sourcing bootstrap credentials from Vault via OCI instance identity**
   instead of a static SSH deploy key stored in an object-storage bucket.

Both changes ship with an **automatic fallback to the current mechanism**
(GitHub + bucket) during the transition, so nothing regresses mid-rollout.

## Pinned decisions (2026-07-21)

1. **Mirror software: Gitea (or the Forgejo fork).** Chosen over productionizing
   `ops-git` after direct comparison (see below). Gitea ships native scheduled
   pull-mirroring, serves git over HTTP/SSH/API with a web UI, exposes a health
   API, and is maintained upstream. Productionizing `ops-git` would mean
   re-implementing all of that (HTTP transport, persistence, sync scheduling,
   monitoring) around a bespoke cron script — i.e. rebuilding Gitea, worse.

2. **Deploy pattern: per-region Nomad service modeled on `nomad/ops-repo.hcl`.**
   `count = 2`, `distinct_hosts`, `general` pool, Consul health check, fronted by
   Fabio via an `int-urlprefix-<hostname>/` tag (internal-only). Datacenter is
   `dc = $ENVIRONMENT-$ORACLE_REGION`, exactly as `deploy-nomad-ops-repo.sh`.

3. **Ephemeral state + re-mirror on restart.** No persistent/host volume. Gitea
   data lives in the container; on restart the replica re-mirrors from GitHub.
   This avoids host-volume/CSI management and shared-state complexity. The cost
   — a cold replica has no data until first sync — is handled by decision 4.
   (Do **not** back Gitea with s3fs like `ops-repo` does: git operations on
   s3fs are slow and unsafe. Ephemeral local disk is correct here.)

4. **Health gate: unhealthy until first sync of all required repos completes.**
   The Consul health check must **not** point at Gitea's own liveness
   (`/api/healthz` goes green as soon as the app starts). Instead a `sync-gate`
   sidecar serves `/ready` on a separate port, returning `503` until every
   required repo reports `"empty": false` (first mirror sync done), then `200`.
   The Nomad `service.check` targets that gate port. During a pool rotation a
   fresh replica registers in Consul but Fabio will not route boot traffic to it
   until it has fully synced. `check_restart { limit = 0 }` so the gate returning
   503 during initial sync never restarts the task.

5. **Repo visibility in Gitea.** Public repos (`infra-configuration`,
   `infra-provisioning`, `jitsi-meet`) are served **anonymously** over the
   internal mirror — booting instances need no credential for them.
   `infra-customizations-private` stays **private** in Gitea and requires a
   read-only Gitea access token (see decision 6). This deliberately avoids
   exposing private source to the whole VCN via anonymous read.

6. **Bootstrap credentials from Vault via OCI instance identity.** A new Vault
   **OCI auth method** (`vault-plugin-auth-oci`) lets an instance authenticate
   with its OCI instance principal — no static secret leaves the instance. A new
   role **`vm-bootstrap`** (covers *all* VM roles, not just JVB), bound to the
   VM compartment OCID / dynamic group, issues a short-lived token scoped by a
   policy that can read **only** two paths:
   - `secret/data/default/gitea/read-token` — the Gitea read-only token for the
     private repo mirror.
   - `secret/data/default/<env>/ansible-vault-password` — the ansible-vault
     password (moved off the bucket).

7. **Fallback to bucket + GitHub during transition.** The boot path attempts
   Vault + regional mirror first; on any failure it falls back to the current
   behavior (fetch key/password from `jvb-bucket-<env>`, clone from GitHub). The
   fallback is removed only after Vault-at-boot has proven durable.

## Comparison: Gitea vs. productionized `ops-git`

| Dimension | Productionized `ops-git` | **Gitea / Forgejo** |
|---|---|---|
| Sync mechanism | Bespoke cron every 1 min → `git clone --mirror` + `git push --mirror`, 50s `timeout`; you own locking/retry | Native scheduled pull-mirror per repo, configurable interval, automatic retry |
| Transport to clients | SSH only today → must be rewritten to smart-HTTP to fit Fabio | HTTP + SSH + REST + web UI out of the box; HTTP routes through Fabio unchanged |
| Client auth | SSH keys required on every instance (the thing we're removing) | Anonymous public read; private repo via a scoped token |
| Sync auth to GitHub | SSH deploy key → mirror's own sync is vulnerable to *this* incident class | Per-mirror HTTPS token → sync avoids the deploy-key failure class |
| HA (count=2) | Two crons hammering GitHub, no shared visibility | Two replicas mirror independently; no shared storage needed |
| Failure visibility | `cat /tmp/update.log` | UI + API show last-sync time and mirror errors; health API |
| Maturity | Personal `aaronkvanmeerten/ops-git:0.0.1`, unmaintained | Maintained upstream image, pinned tag, large community |
| Effort to production | Rewrite transport, add persistence/monitoring/hardening | Adapt one Nomad job + an idempotent seed step |

**Decision: Gitea.** The only edge `ops-git` has is a smaller image, which does
not justify re-implementing maintained software.

## Design

### 5.1 Gitea Nomad job (`nomad/gitea-mirror.hcl`)

Modeled on `nomad/ops-repo.hcl`. Key elements:

- Variables: `dc`, `gitea_hostname`, `image_version` (pinned, e.g.
  `gitea/gitea:1.22-rootless`), `mirror_interval` (default `10m`),
  `required_repos` (list, used by the gate).
- `group "gitea"`: `count = 2`, `distinct_hosts`, `general` pool affinity,
  standard restart stanza. **No `volume` stanza** (ephemeral).
- `network`: `http` (Gitea, `to = 3000`) and `health` (gate, `to = 8080`).
- `task "gitea"`: Gitea configured via `GITEA__<section>__<KEY>` env
  (`INSTALL_LOCK=true`, `DISABLE_REGISTRATION=true`,
  `REQUIRE_SIGNIN_VIEW=false`, `mirror.ENABLED=true`, sqlite at `/data`).
  Admin credentials from Vault (`secret/default/gitea/admin`).
- `service "gitea-mirror"`: `port = "http"`, Fabio tag
  `int-urlprefix-${var.gitea_hostname}/`. **`check`** is `type=http`,
  `port = "health"`, `path = "/ready"`, `check_restart { limit = 0 }`.
- `task "sync-gate"` (`lifecycle { hook = "poststart", sidecar = true }`):
  1. Waits for Gitea, then runs the idempotent mirror seed (see 5.2).
  2. Serves `/ready` on port 8080: `503` until all `required_repos` report
     `"empty": false` via `GET /api/v1/repos/jitsi/<repo>`, then `200`.
  - GitHub sync token from `secret/default/gitea/github`.

Because state is ephemeral, the admin user and mirror config are re-seeded on
every start; the seed is idempotent (create-if-absent), so this is safe.

### 5.2 Mirror seeding (idempotent)

For each repo, check `GET /api/v1/repos/jitsi/<repo>`; if absent, `POST
/api/v1/repos/migrate` with `mirror=true`, `mirror_interval`, correct `private`
flag, and (for the private repo) `auth_token=<github PAT>`. Repos:

- `infra-configuration` (public)
- `infra-customizations-private` (private)
- `infra-provisioning` (public)
- `jitsi-meet` (public)

Sync from GitHub over **HTTPS + token** (not the SSH deploy key) so the mirror's
own sync path is immune to the deploy-key failure class that caused this
incident.

### 5.3 Vault OCI auth (`vm-bootstrap` role)

New Vault configuration (managed alongside the existing `roles/vault` /
`roles/consul-vault` config in infra-configuration):

1. `vault auth enable oci` — enable `vault-plugin-auth-oci`.
2. Configure the home tenancy OCID so Vault trusts instance principals.
3. Role **`vm-bootstrap`** bound to the VM compartment OCID / dynamic group;
   short token TTL (~5–10 min, non-renewable — used once at boot).
4. Policy **`bootstrap-read`** (read-only, nothing else):

   ```hcl
   path "secret/data/default/gitea/read-token"              { capabilities = ["read"] }
   path "secret/data/default/<env>/ansible-vault-password"  { capabilities = ["read"] }
   ```

5. Seed the two secrets in Vault (leave bucket copies in place during
   transition).

### 5.4 Boot path change (`boot-postinstall/files/postinstall-lib.sh`)

Replace the two `oci os object get` calls in `fetch_credentials` with a Vault
login via instance principal, guarded by fallback:

```sh
VAULT_ADDR="https://${VAULT_ENVIRONMENT}-vault.${DNS_ZONE}"
if VAULT_TOKEN=$(vault login -token-only -method=oci \
      auth_type=instance_principal role=vm-bootstrap 2>/dev/null); then
  export VAULT_ADDR VAULT_TOKEN
  vault kv get -field=password secret/default/<env>/ansible-vault-password > /root/.vault-password
  GITEA_TOKEN=$(vault kv get -field=token secret/default/gitea/read-token)
  export INFRA_CONFIGURATION_REPO="https://${GITEA_HOST}/jitsi/infra-configuration.git"
  export INFRA_CUSTOMIZATIONS_REPO="https://oauth2:${GITEA_TOKEN}@${GITEA_HOST}/jitsi/infra-customizations-private.git"
else
  echo "Vault/mirror path failed; falling back to bucket + GitHub"
  $OCI_BIN os object get -bn "jvb-bucket-${ENVIRONMENT}" --name vault-password --file /root/.vault-password
  $OCI_BIN os object get -bn "jvb-bucket-${ENVIRONMENT}" --name id_rsa_jitsi_deployment --file /root/.ssh/id_rsa
  chmod 400 /root/.ssh/id_rsa
  # INFRA_*_REPO stay at the git@github.com SSH URLs (current behavior)
fi
```

`clean_credentials` continues to wipe `/root/.vault-password` (and the key when
the fallback path wrote one).

The regional mirror hostname (`GITEA_HOST`) is injected per region via the
`create-*-instance-configuration` scripts, the same place `INFRA_*_REPO` is set
today.

## Benefits

- **No GitHub availability dependency at boot** — clones come from the regional
  mirror; a GitHub outage only stalls mirror *sync* (serving the last snapshot,
  staleness ≈ mirror interval).
- **No static bootstrap secret on the instance or in the bucket** — identity is
  the OCI instance principal; the deploy key is eliminated once the fallback is
  removed.
- **Least-privilege credentials** — the `vm-bootstrap` token can read only the
  Gitea read-token and the ansible-vault password, nothing else in Vault.
- **Regional** — a booting VM clones from its own region's mirror; no
  cross-region egress or single-region dependency at boot.
- **Reuses proven infrastructure** — the `ops-repo.hcl` Nomad/Consul/Fabio/Vault
  pattern already runs in production for the apt (`download-repo`) and Docker
  (`registry`) mirrors.

## Risks and mitigations

- **Vault-at-boot dependency.** This moves boot-time secret fetching from OCI
  object storage (effectively always-up) to Vault, which had a **seal outage on
  2026-07-09 (ops-prod)**. If Vault is sealed/unreachable, boots would fail at
  `fetch_credentials` — a wider blast radius than today.
  *Mitigation:* (a) bucket + GitHub fallback retained for the whole transition
  (decision 7); (b) hard cutover (removing the fallback) is gated on the Vault
  seal-watchdog / HA work from the 2026-07-09 incident being in place and
  proven.
- **Mirror staleness during a GitHub outage.** Instances boot against the last
  successful sync. Acceptable for VMs tracking `main`/release tags; a branch
  newer than the last sync would not be present until GitHub recovers.
- **Private source on the internal mirror.** Kept private in Gitea behind a
  scoped read token (decision 5/6) rather than served anonymously.
- **Cold replica after rotation.** Handled by the first-sync health gate
  (decision 4): a not-yet-synced replica is never routed to.

## Rollout plan

1. Stand up the Gitea mirror per region (`nomad/gitea-mirror.hcl` +
   `scripts/deploy-nomad-gitea-mirror.sh`, modeled on the `ops-repo`
   equivalents). Seed mirrors; verify sync and the first-sync health gate.
2. Enable Vault OCI auth + `vm-bootstrap` role + `bootstrap-read` policy; seed
   the two Vault secrets. Leave bucket copies in place.
3. Ship the `fetch_credentials` change **behind the fallback**. Canary on
   `stage-8x8`, then one prod region.
4. Flip `INFRA_*_REPO` per region to the mirror (GitHub remains the fallback).
5. Once stable, remove the deploy key and `vault-password` from the buckets and
   retire the fallback — gated on the Vault seal mitigations (see Risks).

## Open questions

- Which compartment OCID / dynamic group should the `vm-bootstrap` role bind to
  per environment?
- Mirror `jitsi-meet` in all regions, or only where boots need it?
- Confirm the per-env `VAULT_ENVIRONMENT` / `DNS_ZONE` values used to construct
  `VAULT_ADDR` at boot for each environment.

## References

- Root-cause dump: `prod-8x8-jvb-66-97-202-2026-07-21-1103--dump.tar.gz`
  (`postinstall-ansible.log`, `cloud-init-output.log`).
- Existing mirror pattern: `nomad/ops-repo.hcl`, `nomad/download-repo.hcl`,
  `nomad/registry.hcl`, `scripts/deploy-nomad-ops-repo.sh`.
- Prior bootstrap-repos work: infra-configuration PR #207 (add), PR #211
  (backout), PR #900 (object-cache); role `ansible/roles/bootstrap-repos/`.
- Prototype git mirror: `docker/ops-git/` (`update-repos.sh`).
- Boot path: `ansible/roles/boot-postinstall/files/postinstall-lib.sh`
  (`checkout_repos`, `fetch_credentials`).
- Gitea mirroring: https://docs.gitea.com/usage/repo-mirror (pull mirrors);
  admin/migrate API: https://docs.gitea.com/api/next/
- Vault OCI auth method: https://developer.hashicorp.com/vault/docs/auth/oci
  and plugin https://github.com/hashicorp/vault-plugin-auth-oci
- Related: 2026-07-09 Vault seal outage (seal-watchdog/probe/runbook work).
- GitHub incident 2026-07-21: deploy-key SSH authentication failures.
