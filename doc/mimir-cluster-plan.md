# Plan: Production-Grade Mimir Cluster to Replace Regional Prometheus

Status: PROPOSED (not yet implemented)
Tracking: JIT-16016 (this plan) / JIT-16017 (alert-catalog → ruler + Mimir HA alertmanager follow-up)
Author: generated 2026-07-08

## Pinned decisions (2026-07-08)

1. **Mimir version: `3.1.2`** (latest stable, released 2026-06-24). Mimir 3.x
   still supports the classic architecture (distributor → ingester direct; the
   Kafka "ingest storage" path is optional) and monolithic `-target=all` mode —
   only the experimental read-write deployment mode was removed. Fresh-deploy
   notes: the Mimir Query Engine (MQE) is now the default query engine (fine
   for a new deployment; `-querier.query-engine=prometheus` exists as an
   escape hatch), and deprecated 2.x flags are gone, so config examples must be
   validated against 3.x docs, not 2.x blog posts.
2. **S3 credentials: dedicated Vault kv `secret/default/mimir/s3`** (tempo
   pattern), scoped to the mimir bucket only. Do NOT reuse
   `nomad_s3fs_credentials`.
3. **Alert-rule rendering: YAML fragments composed with `yq` in the deploy
   script.** The catalog is split into per-flag fragment files (base, system,
   cloudprober, core, core-extended, autoscaler, prod-overrides) and the
   deploy script assembles the mimirtool-format rule namespaces from the same
   env flags the prometheus deploy script reads today — no re-implementation
   of Terraform `%{ if }` templating. (Execution of this is in the follow-up
   ticket below, but the approach is decided.)
4. **Alloy is the only metrics writer — no other remote_write anywhere.**
   All metrics already flow through Alloy (or should); it gains the consul-SD
   scrape jobs and writes every stream to BOTH the local Mimir and the
   external 8x8-hosted Mimir (the endpoint in
   `secret/default/prometheus/remote_write/<env_type>` — that Vault secret
   with its `X-Scope-OrgID` tenant header moves to Alloy's config).
   prometheus.hcl's `remote_write` block is **removed in Phase 2**, not at
   cutover — old prometheus becomes a purely local alert evaluator. No new
   `prometheus-agent.hcl`, no Prometheus remote-write code path anywhere.
   HA dedup via Mimir's HA tracker (both alloys scrape everything with
   `cluster`/`__replica__` labels); verify the external 8x8 Mimir tenant has
   HA dedup enabled for the same labels before enabling the second replica's
   external write.
5. **Stable Mimir ring identity + rotation health gates.** Each group pins
   `-ingester.ring.instance-id=mimir-<N>` with `tokens_file_path` on its host
   volume, so consul-node rotations and alloc reschedules rejoin the ring as
   the *same* member (no unhealthy squatters, no token churn). The
   rotate-consul path gains Mimir/Loki-aware health gates (see §5a).

## Scope changes (2026-07-08)

- **Alert catalog extraction + Mimir alertmanager support → JIT-16017.**
  Phase 3 below is descoped from this plan and tracked in its own ticket,
  which also covers evaluating Mimir's built-in HA alertmanager as the
  replacement for the single-instance alertmanager.hcl. Consequence for this
  plan: the existing regional Prometheus stays running as the *alert
  evaluator only* until that ticket lands; its decommission (Phase 6) is gated
  on it.
- **No autoscaler repointing needed.** No autoscaler currently queries
  Prometheus, so the Phase 4 consumer-inventory risk is dropped; the query
  path flip is Grafana datasources only.
- **prometheus-agent.hcl dropped; remote_write eliminated as a concept**
  (pinned decision #4): all metrics funnel through the existing Alloy
  collector, which writes to the local Mimir AND the external 8x8-hosted
  Mimir (the original remote_write target). prometheus.hcl loses its
  remote_write block in Phase 2 and keeps only local alert evaluation.
- **Consul rotation intelligence added to scope** (§5a): the
  `jenkins/groovy/rotate-consul` path replaces its blind between-pool sleep
  with Mimir/Loki health gates so consul/mimir servers rotate safely.

## 1. Goals

- Replace the single-instance, single-point-of-failure regional Prometheus
  ([nomad/prometheus.hcl](../nomad/prometheus.hcl)) with a highly-available,
  always-on Grafana Mimir cluster.
- Bucket-backed (OCI Object Storage, S3-compat) long-term metric storage so
  metric history survives instance loss and is not bounded by block-volume size.
- Multi-instance cluster per region, mirroring the
  [nomad/loki-cluster.hcl](../nomad/loki-cluster.hcl) pattern (3 replicas on the
  consul pool, memberlist ring, host volumes from OCI block volumes).
- Zero-downtime deploys and upgrades (rolling, health-gated, replication-aware).
- Grafana dashboards + alert rules to monitor Mimir itself.
- Keep the existing alert-rule catalog working with no alerting gap: the
  current Prometheus keeps evaluating it until the follow-up ticket moves the
  catalog to the Mimir ruler (see Scope changes above).

### Non-goals (for the first iteration)

- Multi-tenancy (run with `multitenancy_enabled: false`; can be enabled later).
- Replacing the external 8x8-hosted Mimir feed (the Vault-driven
  `secret/default/prometheus/remote_write/*` endpoint). The feed continues
  unchanged — only its writer moves from prometheus.hcl to Alloy (Phase 2).
- Centralizing metrics across regions into one global Mimir. We keep the
  per-region topology to match Loki/Tempo and the per-DC alerting model.
  (A future phase could add a per-environment "global" Mimir fed by all regions;
  noted in §10.)

## 2. Current state (what we're replacing)

| Aspect | Today |
|---|---|
| Deployment | 1× `prom/prometheus:v2.55.1` per env-region, `count = 1`, consul pool |
| Storage | Single 500 GB OCI block volume (`terraform/volume-prometheus/`), host volume `prometheus` — data lost/stranded if the volume or AD has problems, no HA |
| Scraping | Prometheus itself scrapes consul-discovered services (`alertmanager`, `cloudprober`, `telegraf`, self) |
| Writes in | Alloy remote-writes to `https://<env>-<region>-prometheus.<tld>/api/v1/write` ([nomad/alloy.hcl:260](../nomad/alloy.hcl)) — `--web.enable-remote-write-receiver` |
| Writes out | Vault secret `secret/default/prometheus/remote_write/<env_type>` → external 8x8-hosted Mimir (X-Scope-OrgID tenant header) |
| Alerting | Huge templated `alerts.yml` rendered in the job; Alertmanager found via Consul SD; nonprod severity downgrade; global alertmanager option |
| Queries | Grafana datasource, alert `alert_url` links (no autoscaler queries — confirmed 2026-07-08) |
| Ingress | Fabio `int-urlprefix-` tag + CNAME to the general-pool internal LB |
| Deploy | `scripts/deploy-nomad-prometheus.sh`, Jenkins `provision-nomad-prometheus.yaml` / `release-nomad-prometheus.yaml` |

Single `count = 1` group means every deploy, OS patch, or node failure is a
metrics + alert-evaluation outage. That is the core problem.

## 3. Target architecture

Grafana Mimir in **monolithic mode** (`-target=all`), 3 instances per region:

```
                       ┌─────────────────────────────────────────────┐
 alloy ×2 (scrape +    │  mimir-cluster.hcl  (consul pool, 3 nodes)  │
 OTLP + remote_write) ─┼─► distributor ─► ingester (RF=3, zone aware)│
                       │        │                │ TSDB blocks       │
                       │   HA dedup (consul KV)  ▼                   │
                       │                 OCI Object Storage          │
 grafana ──────────────┼─► query-frontend ─► querier ─► store-gateway│
                       │   ruler ──► alertmanager (consul SD)        │
                       └─────────────────────────────────────────────┘
```

Key decisions:

1. **Monolithic mode, 3 replicas** — same operational shape as loki-cluster
   (3 groups `mimir-0/1/2`, one per consul node / availability domain). All
   Mimir components run in each instance; the memberlist ring coordinates them.
   Microservices mode is overkill at our per-region scale and would explode the
   Nomad job complexity.
2. **`replication_factor: 3` + zone-awareness** — unlike loki-cluster (RF=1!),
   we run RF=3 with each group assigned a zone (`zone-a/b/c` mapped from the
   group index / AD). Any single instance or AD can be lost with no data loss
   and no write outage; rolling upgrades restart one zone at a time.
3. **Bucket-backed blocks storage** — TSDB blocks ship to
   `mimir-<environment>` bucket (per-region, same pattern as `loki-<environment>`),
   with prefixes `blocks/`, `ruler/`, `alertmanager/` (one bucket, three
   `storage_prefix`es — avoids 3× bucket sprawl). Local block volumes hold only
   the ingester WAL + 2h head block + compactor scratch, so 100 GB volumes
   (loki-sized) are sufficient, vs. today's 500 GB.
4. **Scraping moves out of the TSDB, into Alloy** — Mimir has no scraper. The
   existing **Alloy deployment** (count=2) gains `discovery.consul` +
   `prometheus.scrape` components replicating today's scrape jobs, and its
   remote_write is the single write path to Mimir. Both replicas scrape
   everything and send `cluster`/`__replica__` external labels; Mimir's
   **HA tracker** (backed by local Consul KV at `<node>:8500`) deduplicates —
   scraping is now also HA, which it never was before. (Alloy native
   clustering/target-sharding is the fallback option if double-scrape load
   ever matters; dedup was chosen because it has zero-gap failover.)
5. **Ruler eventually evaluates the existing alert catalog** — the templated
   `alerts.yml` moves into Mimir ruler rule groups via `mimirtool rules sync`
   (see pinned decision #3), tracked in the separate alert-extraction ticket.
   Until then the old prometheus job keeps evaluating alerts against its own
   scrapes.
6. **Prometheus-compatible query API** — Grafana/autoscaler point at
   `https://<env>-<region>-mimir.<tld>/prometheus` (Mimir's default
   `prometheus_http_prefix`). Fabio routing + CNAME stack identical to loki.

### Ports and gossip

- HTTP: dynamic Nomad port (Mimir `http_listen_port` templated from
  `NOMAD_HOST_PORT_http`, like loki).
- gRPC: dynamic port.
- memberlist gossip: **static 7947** — loki-cluster already owns static 7946 on
  the same consul nodes, so Mimir must use its own static port. Join members:
  `${dc}-consul-{a,b,c}.${internal_dns_zone}:7947`, same DNS pattern as loki.

### Sizing (initial)

| Env type | CPU | Memory per instance | Notes |
|---|---|---|---|
| nonprod | 1000 MHz | 3 GB | |
| prod | 2000 MHz | 8 GB | today's prom uses 6 GB alone; ingesters hold the series in RAM ×3 replicas |

Consul-pool nodes will run loki + mimir + (during migration) prometheus
simultaneously — **verify consul-node shapes have headroom before prod rollout**
(Phase 0 checklist). Prod may need the consul pool bumped one shape.

Measured 2026-07-08 on beta / us-ashburn-1 (nonprod, 4 cores / 8000 MHz /
16 GiB nodes):

| Node | Volumes | Alloc CPU | Alloc Mem | Notable allocs |
|---|---|---|---|---|
| consul-83-134-124 | loki-1, redis-1 | 2452/8000 MHz | 6.0/16 GiB | alertmanager, vector, telegraf |
| consul-83-141-181 | loki-2, redis-2 | 3914/8000 MHz | 7.7/16 GiB | autoscaler, alert-emailer, canary |
| consul-83-157-68 | loki-0, prometheus, redis-0 | 2952/8000 MHz | 7.5/16 GiB | prometheus (2 GiB) |

Actual OS-level usage is low (2.4 GiB used on the sampled node). Adding a
3 GiB nonprod mimir instance per node lands at ~9–10.7 GiB allocated of
16 GiB, fitting even during the dual-run migration window. Prod (6 GiB
prometheus + 8 GiB mimir proposal) still needs its own check before rollout.

## 4. Implementation phases

### Phase 0 — Infrastructure prerequisites

New/changed files:

1. `terraform/volumes-mimir/` — copy of `terraform/volumes-loki/`
   (`volume_count = 3`, 100 GB, tags `volume-type = "mimir"`,
   `volume-role = "consul"`, `volume-index = N`). The existing
   `postinstall-lib.sh` `mount_volumes()` + ansible nomad role already turn any
   `/mnt/bv/mimir-N` mount into a registered Nomad host volume — no ansible
   change needed, but **consul nodes must be re-run/rotated** to attach + mount
   the new volumes (same procedure used when loki volumes were introduced).
2. `scripts/create-buckets-oracle.sh` — add
   `BUCKET_NAME="mimir-$ENVIRONMENT"` (no lifecycle policy; the Mimir
   compactor owns retention via `-compactor.blocks-retention-period`).
3. Secrets: mint the dedicated Vault kv `secret/default/mimir/s3` (tempo
   pattern; pinned decision #2) so mimir creds can be rotated independently.
4. Capacity check on consul pool (memory/CPU/AD spread) per environment.

### Phase 1 — `nomad/mimir-cluster.hcl` + deploy script + Jenkins

`nomad/mimir-cluster.hcl`, modeled directly on loki-cluster.hcl:

- `dynamic "group"` over `[0, 1, 2]` → groups `mimir-0/1/2`, `count = 1` each,
  host network, consul-pool constraint, host volume `mimir-${group.key}`,
  `distinct_hosts`/AD spread implicit via volume placement.
- Image `grafana/mimir:3.1.2` (`mimir_version` variable like
  `prometheus_version` today).
- Config template highlights:

```yaml
multitenancy_enabled: false
server:
  http_listen_port: {{ env "NOMAD_HOST_PORT_http" }}
  grpc_listen_port: {{ env "NOMAD_HOST_PORT_grpc" }}
  log_level: warn
common:
  storage:
    backend: s3
    s3: # OCI S3-compat endpoint, same shape as loki/tempo
      endpoint: <ns>.compat.objectstorage.<region>.oraclecloud.com:443
      bucket_name: mimir-<environment>
blocks_storage:
  storage_prefix: blocks
  tsdb: { dir: /mimir/tsdb }          # host volume
  bucket_store: { sync_dir: /mimir/tsdb-sync }
ruler_storage:  { storage_prefix: ruler }
memberlist:
  advertise_addr: {{ env "NOMAD_IP_grpc" }}
  bind_port: 7947
  join_members: [<dc>-consul-{a,b,c}.<zone>:7947]
ingester:
  ring:
    replication_factor: 3
    zone_awareness_enabled: true
    instance_availability_zone: zone-${group.key}
    instance_id: mimir-${group.key}   # stable identity across node rotations
    tokens_file_path: /mimir/tokens   # on the host volume — tokens survive too
    unregister_on_shutdown: false     # rolling restarts don't reshard
    final_sleep: 0s
store_gateway:
  sharding_ring: { replication_factor: 3, zone_awareness_enabled: true, ... }
distributor:
  ha_tracker:
    enable_ha_tracker: true
    kvstore: { store: consul, consul: { host: <node>:8500 } }
compactor:
  data_dir: /mimir/compactor
  blocks_retention_period: ${var.retention_period}   # default e.g. 2160h/90d
ruler:
  rule_path: /mimir/ruler
  alertmanager_url: consul-SD equivalent (static list templated from consul
    service via consul-template `{{ range service "alertmanager" }}`)
limits:
  max_global_series_per_user: 0 or sized cap
  ingestion_rate: sized
  out_of_order_time_window: 5m       # tolerate agent replay after restarts
```

- `update` stanza (zero-downtime rolling — see §5).
- Service `mimir` with `int-urlprefix-${var.mimir_hostname}/` tag, health check
  `GET /ready`, `check_restart` like loki.

`scripts/deploy-nomad-mimir.sh` — copy of deploy-nomad-loki.sh: renders
`[JOB_NAME]` → `mimir-$ORACLE_REGION`, exports hostname/namespace/creds vars,
runs the job, then `create-oracle-cname-stack.sh` for
`<env>-<region>-mimir.<tld>`.

Jenkins (in this repo's `jenkins/jobs/` + reuse of the generic
`provision-nomad-job` Jenkinsfile):

- `provision-nomad-mimir.yaml` (JOB_TYPE=mimir).
- `release-nomad-mimir.yaml` + `jenkins/groovy/release-nomad-mimir/Jenkinsfile`
  cloned from the release-nomad-prometheus pipeline (multi-region, governance
  params, RP ticket support).

Validate the whole phase on **lonely** first (established pattern).

### Phase 2 — Write path (Alloy does all scraping + remote_write)

All changes land in `nomad/alloy.hcl` (pinned decision #4 — no new scraper
job, no Prometheus-agent remote-write in the picture):

1. **Scrape components**: add `discovery.consul` + `prometheus.scrape` blocks
   replicating today's prometheus.hcl scrape jobs — `alertmanager`,
   `cloudprober`, `telegraf` (30s interval), **plus new `mimir` and `alloy`
   self jobs** — with the same `service` metric-relabels and the
   `custom_relabels` var equivalents.
2. **Labels for HA dedup**: `external_labels` carry
   `datacenter/environment/region` (as prometheus does today) plus
   `cluster: <env>-<region>` and `__replica__: <alloc-id>` so both alloy
   replicas can scrape everything and each Mimir keeps exactly one copy.
   Prerequisite: confirm the external 8x8 Mimir tenant has HA dedup enabled
   for these labels; until confirmed, only one alloy replica forwards to the
   external endpoint.
3. **Two write destinations, one writer**: every stream (scraped + OTLP)
   forwards to (a) the local Mimir at
   `https://<env>-<region>-mimir.<tld>/api/v1/push` — replacing the current
   `prometheus.remote_write "default"` that points at old prometheus — and
   (b) a new `prometheus.remote_write "external_8x8"` built from the
   `secret/default/prometheus/remote_write/<env_type>` Vault secret
   (endpoint, basic auth, `X-Scope-OrgID` header), which is the external
   8x8-hosted Mimir that prometheus.hcl writes to today.
4. **prometheus.hcl loses its `remote_write` block in this phase** — Alloy is
   now the only writer to the external Mimir, and old prometheus becomes a
   purely local scrape-and-evaluate alert engine until the ruler ticket
   retires it. No Prometheus remote-write code path remains anywhere.
5. **Resources**: bump the alloy task from 256 MHz / 512 MB (sized as an OTLP
   relay) to cover the scrape + WAL load — start at 512 MHz / 1.5 GB and let
   the alloy-monitor dashboard calibrate.

### Phase 3 — Alert rules on the ruler [MOVED TO JIT-16017]

Descoped from this plan (see Scope changes at top). The follow-up ticket
covers:

1. Extracting the alert catalog from prometheus.hcl into per-flag YAML
   fragments composed by `yq` in a deploy script (pinned decision #3), synced
   via `mimirtool rules sync --address=https://<mimir_hostname> --id=anonymous`
   (idempotent, diff-based; rules land in the `ruler/` bucket prefix and the
   three rulers shard evaluation).
2. Nonprod `severe→warn` rewrite + global-alertmanager `scope=global` fan-out
   parity in the ruler's alertmanager client config.
3. Updating `alert_url` annotations away from the Prometheus UI links.
4. **Mimir alertmanager support**: evaluate Mimir's built-in HA alertmanager
   (3 replicas over the same ring, `alertmanager/` bucket prefix for state)
   as the replacement for the single-instance alertmanager.hcl SPOF.

Until that ticket lands, prometheus.hcl keeps running as the alert evaluator
(scraping + rule evaluation only; its storage/query duties end at Phase 4-5).

The Mimir *self*-monitoring alerts in §6 are NOT deferred — they ship with
this plan, added to the existing prometheus.hcl alert template (a small
`mimir_alerts` group) plus a consul-SD scrape job for the `mimir` service in
prometheus.hcl, so the current evaluator watches the new cluster from day
one. They migrate to the ruler with everything else later.

### Phase 4 — Query path

1. Grafana: repoint (or add alongside during migration) the per-region
   Prometheus datasource to `https://<env>-<region>-mimir.<tld>/prometheus`.
   This is the only query consumer to flip — no autoscaler uses Prometheus
   (confirmed 2026-07-08), and a belt-and-braces
   `grep -r prometheus_hostname` across the infra repos at implementation time
   costs nothing.
2. The old `<env>-<region>-prometheus` CNAME stays alive regardless until the
   deferred Phase 6 (prometheus keeps running as alert evaluator until the
   ruler ticket lands).

### Phase 5 — Migration & cutover (per environment: lonely → stage → prod)

1. Deploy Mimir cluster, then the Alloy changes; Alloy dual-writes its OTLP
   streams to both old Prometheus and local Mimir during the soak, and its
   new scrape streams to local + external Mimir. Old Prometheus keeps its own
   scraping + alerting — **no alerting gap**.
2. Soak: compare query results old-vs-new in Grafana (side-by-side
   datasources), verify HA dedup (no doubled series), verify blocks appear in
   the bucket after ~2h and are queryable after compactor runs.
3. Flip Grafana datasources to Mimir once the overlap window covers the
   operationally interesting lookback (suggest ≥15 days, matching
   Prometheus's local retention — there is no practical backfill from
   Prometheus TSDB to Mimir, history simply ages in).
4. Prometheus stays running as the alert evaluator (rule evaluation only —
   queries/dashboards now hit Mimir) until the ruler/alertmanager follow-up
   ticket completes; full decommission is Phase 6, gated on that ticket.
5. Prod rollout gated by governance (RP ticket per the release pipeline).

### Phase 6 — Decommission [GATED on JIT-16017]

Once alert evaluation has moved to the Mimir ruler:

- Delete the prometheus.hcl job entirely (scraping and the external-Mimir
  push will already live in Alloy; alerting in the ruler).
- Delete `provision/release-nomad-prometheus` Jenkins jobs or repoint them.
- Stop the job, keep the 500 GB volume ~30 days as cold fallback, then remove
  the `volume-prometheus` terraform via its destroy path.

## 5. Zero-downtime upgrade strategy

Nomad-level (in mimir-cluster.hcl):

```hcl
update {
  max_parallel      = 1        # one group (= one zone) at a time
  health_check      = "checks"
  min_healthy_time  = "30s"
  healthy_deadline  = "5m"
  progress_deadline = "10m"
  auto_revert       = true
  stagger           = "60s"
}
```

Mimir-level guarantees that make max_parallel=1 truly zero-downtime:

- RF=3 + zone-awareness: writes need 2/3 ring members; restarting one zone
  keeps quorum. Queries fan out to remaining store-gateways/ingesters.
- `ingester.ring.unregister_on_shutdown: false` +
  `min_ready_duration`: restarts don't trigger ring resharding/handovers.
- WAL on the persistent host volume: the restarted ingester replays and
  rejoins with no sample loss; `out_of_order_time_window` absorbs agent
  retries.
- `shutdown_delay = "10s"` + Fabio health-check removal drains queries before
  SIGTERM (same as loki).
- The HA scraper pair + retry-on-5xx in remote write means even a distributor
  blip loses nothing (samples buffer in the agent WAL).

Upgrade runbook (documented in the doc/ runbook, encoded in the release job):

1. Read Mimir release notes; Mimir supports N→N+1 rolling upgrades — never
   skip more than one minor version.
2. Bump `mimir_version` default, deploy to lonely, watch the Mimir dashboards
   (§6) for: ring health, discarded samples, compactor success, query p99.
3. Release pipeline rolls region-by-region (REGIONS param), one group at a
   time within each region; `auto_revert` restores the old version if health
   checks fail.
4. Config-only changes follow the same path (template change → new job
   version → rolling).
5. For breaking-config releases, use the same dual-flag pattern Grafana
   documents (deploy config compatible with both versions first, then bump
   image).

### 5a. Consul-node rotation with Mimir awareness (rotate-consul path)

Today `jenkins/groovy/rotate-consul/Jenkinsfile` →
`scripts/rotate-consul-oracle.sh` rotates the three single-instance consul
pools a→c sequentially: pre-detach drains Nomad and does `consul leave`
(`rotate-consul-pre-detach.sh`), post-attach restores the keyring and re-runs
terraform (`rotate-consul-post-attach.sh`), and the only pacing between pools
is a **blind `sleep 150`**. Once each consul node carries a Mimir ingester,
that blind sleep is the failure mode: if pool-b's rotation begins before
mimir on the new pool-a node has reattached its volume, replayed its WAL, and
gone ACTIVE in the ring, the cluster is at 2/3 — and a further hiccup means a
write outage. (Loki has the same exposure today with RF=1 and nothing gates
it; these gates fix that for free.)

Changes (same philosophy as the autoscaler rotation health gate, PR #1117 —
never take down instance N+1 until instance N's replacement is proven
healthy):

1. **Stable ring identity** (pinned decision #5): `instance_id: mimir-<N>` +
   `tokens_file_path` on the host volume mean the rescheduled ingester rejoins
   as the same ring member with the same tokens — a rotation never creates an
   unhealthy ring squatter, so no `forget` step is needed in the happy path.
2. **Pre-detach gate** (in `rotate-consul-pre-detach.sh`, before the nomad
   drain): query the local Mimir ring (`/ingester/ring` or
   `cortex_ring_members` via the query API) and require 3 ACTIVE / 0
   unhealthy ingesters, plus loki `/ready` on all three. If the cluster is
   already degraded, **abort the rotation** instead of making it worse.
3. **Post-attach gate** (new `scripts/consul-metrics-health-gate.sh`, called
   from `rotate-consul-oracle.sh` in place of the blind sleep): poll until
   (a) the new node registers in Nomad with its `mimir-N`/`loki-N` host
   volumes, (b) the mimir-N and loki-N allocs are running, (c) mimir `/ready`
   returns 200 and the ring is back to 3 ACTIVE / 0 unhealthy, (d) loki
   `/ready` returns 200. Configurable timeout (default 15m); on timeout the
   pipeline **fails loudly** rather than rolling on to the next pool.
4. **Jenkinsfile**: add `HEALTH_GATE` (default `true`; escape hatch for
   disaster recovery when the gate can never pass) and
   `HEALTH_GATE_TIMEOUT_MINUTES` parameters, and echo gate progress so the
   rotation log shows what it waited on.

## 6. Monitoring the monitor

### Self-metrics

The Alloy pair scrapes each Mimir instance's `/metrics` (job `mimir`) and its
own `/metrics` (job `alloy`), writing to both the local Mimir and the external
8x8-hosted Mimir. Sending Mimir's own health metrics to the **external** stack
solves "who watches the watcher": if the regional Mimir is down, its absence
still alerts from the external stack (mirrors the existing global-alertmanager
design).

### New alert rules (evaluated by the existing prometheus.hcl initially, migrating to the ruler with the follow-up ticket; starred ones also mirrored to the external stack)

| Alert | Expr sketch | Severity |
|---|---|---|
| *Mimir_Down | `absent(up{job="mimir"})` | severe/page |
| Mimir_Instance_Down | `count(up{job="mimir"} == 1) < 3` | warn (5m) / severe (30m) |
| Mimir_Ring_Unhealthy | `cortex_ring_members{state="Unhealthy"} > 0` | severe |
| Mimir_Ingestion_Discards | `rate(cortex_discarded_samples_total[5m]) > 0` sustained | warn |
| Mimir_HA_Dedup_Flapping | `rate(cortex_ha_tracker_replicas_cleanup_total[10m])` anomaly | smoke |
| Mimir_Compactor_Stalled | `time() - cortex_compactor_last_successful_run_timestamp_seconds > 4h` | severe |
| Mimir_StoreGateway_Sync_Failing | `rate(cortex_bucket_stores_blocks_sync_failures_total[10m]) > 0` | warn |
| Mimir_Object_Storage_Errors | `rate(thanos_objstore_bucket_operation_failures_total[5m]) > 0` | warn→severe |
| Mimir_Query_Latency_High | p99 `cortex_request_duration_seconds` (query path) > 10s | warn |
| Mimir_Write_Latency_High | p99 push duration > 1s | warn |
| Mimir_Ruler_Failing | `rate(cortex_ruler_rule_evaluation_failures_total[5m]) > 0` | severe (rule evals ARE our alerting) |
| *Alloy_Scrape_Down | `absent(up{job="alloy"})` or `count(up{job="alloy"}) < 2` | severe |
| Alloy_RemoteWrite_Backlog | `prometheus_remote_storage_highest_timestamp_in_seconds - prometheus_remote_storage_queue_highest_sent_timestamp_seconds > 60` per endpoint | warn→severe |
| Mimir_Memory_High | existing Nomad_Job_Memory_Use_High covers it — remove the `task!~"prometheus"` exclusion carve-out decision for mimir deliberately |

Also: a **cloudprober http probe** against `https://<mimir_hostname>/ready` and
a synthetic **query probe** (instant query `vector(1)` via
`/prometheus/api/v1/query`) — end-to-end read-path checking, matching how other
services are probed here.

### Grafana dashboards (new JSONs in `grafana/dashboards/`)

Base them on the upstream **mimir-mixin** (compiled, then trimmed to
single-tenant/monolithic reality), following the style of the existing
`alloy-monitor.json`:

1. `mimir-overview.json` — cluster up-count, ingestion rate (samples/s),
   active series, in/out bytes, ring status, per-instance memory/CPU (from
   telegraf/nomad metrics), object-storage op rate + errors.
2. `mimir-writes.json` — distributor push QPS/latency/errors, HA tracker
   elected replica per cluster, ingester appends, WAL fsync latency,
   discarded-sample reasons, out-of-order counts.
3. `mimir-reads.json` — query-frontend QPS + p50/p99, querier fanout,
   store-gateway block sync/lazy-load stats, cache hit rates (if/when we add
   memcached), slow queries table.
4. `mimir-ruler-compactor.json` — rule group evaluation duration vs interval,
   missed evaluations, notifications sent/failed to Alertmanager, compactor
   runs/duration/blocks compacted, bucket blocks by resolution, retention
   deletions.
5. Extend the existing `alloy-monitor.json` — scrape target counts, scrape
   duration, WAL size, remote-write lag/shards/retries per endpoint (local
   Mimir + external 8x8 Mimir) — remote-write backlog is the #1 early-warning
   signal.

Provisioning stays as today (dashboards land in the repo dir and are imported
via the existing grafana flow).

## 7. Production-hardening checklist

- [ ] **Limits configured, not default-unlimited**: `ingestion_rate`,
  `ingestion_burst_size`, `max_global_series_per_user`,
  `max_label_names_per_series`, query limits (`max_fetched_chunks_per_query`,
  `max_query_parallelism`) — sized from current prod series counts
  (`prometheus_tsdb_head_series` today ≈ derive per region before setting).
- [ ] **Retention deliberate**: `blocks_retention_period` var (default 90d;
  today we effectively have ~15d locally + the external 8x8 Mimir), documented per env.
- [ ] **Consul-pool capacity** re-validated per env; instance shapes bumped if
  loki+mimir co-tenancy pushes memory > 70%.
- [ ] **Bucket security**: dedicated S3 credential (`secret/default/mimir/s3`),
  scoped IAM policy to only the mimir bucket (follow the ops-repo-test
  compartment/IAM lessons), no versioning (compactor churns objects),
  no lifecycle rule (compactor owns deletes).
- [ ] **Gossip port 7947** allowed in the consul-pool security list (verify
  the same rule that opened 7946 for loki; extend it).
- [ ] **Backpressure tested**: kill 1 and 2 mimir instances in lonely under
  load; verify alloy buffers + recovers with no gaps (2-instance loss = expected
  partial write failure with RF=3 — verify alerting catches it).
- [ ] **Load test** with a realistic series count (e.g. `avalanche` or replay
  from prod remote-write on stage) before prod cutover.
- [ ] **Runbook** (`doc/mimir-runbook.md`): rolling restart, replacing a
  failed volume/instance (forget ring member procedure), compactor stuck,
  bucket credential rotation, disaster recovery (cluster rebuild from bucket —
  blocks are the source of truth; a full rebuild loses only the un-shipped ≤2h
  head, which the alloy WAL + external 8x8 Mimir copy cover).
- [ ] **Backup/DR stance documented**: bucket is single-region; accepted risk
  (same stance as loki), long-term copy exists in the external 8x8 Mimir.
- [ ] **Governance**: prod rollout via release pipeline with RP ticket,
  region-by-region with soak between regions.

## 8. File-by-file change list

| File | Action |
|---|---|
| `nomad/mimir-cluster.hcl` | NEW — 3-group monolithic Mimir cluster |
| `nomad/alloy.hcl` | EDIT — consul-SD scrape components, HA-dedup labels, writes to local mimir `/api/v1/push` + external 8x8 mimir (vault secret moves here), resource bump |
| `nomad/prometheus.hcl` | EDIT — add `mimir` scrape job + `mimir_alerts` group; DELETE later in Phase 6 (gated on ruler ticket) |
| `scripts/deploy-nomad-mimir.sh` | NEW — job deploy + CNAME (`mimirtool rules sync` added by follow-up ticket) |
| `scripts/create-buckets-oracle.sh` | EDIT — add `mimir-$ENVIRONMENT` bucket |
| `terraform/volumes-mimir/` | NEW — 3× 100 GB block volumes, consul role, indexed |
| `jenkins/jobs/provision-nomad-mimir.yaml` | NEW (generic provision-nomad-job Jenkinsfile) |
| `jenkins/jobs/release-nomad-mimir.yaml` + groovy pipeline | NEW — clone of release-nomad-prometheus |
| `grafana/dashboards/mimir-*.json` (×4) | NEW; `alloy-monitor.json` EDIT (remote-write/scrape panels) |
| `doc/mimir-runbook.md` | NEW |
| sites/*/vars & stack-env | EDIT — retention/sizing overrides per env as needed |

## 9. Rollout order

1. lonely: Phases 0–4, soak 1–2 weeks, kill-testing + load test.
2. stage/other nonprod: same, shorter soak.
3. prod, region by region (release pipeline REGIONS param), dual-write soak
   ≥15 days per region before datasource flip; decommission last.

## 10. Open questions / future work

- **Central per-environment Mimir**: regional alloys could write to one
  self-hosted global Mimir (subsuming the external 8x8 feed?) for
  cross-region queries.
  Deferred — changes the alerting locality model.
- **Memcached** for chunks/index/results caches: Mimir runs fine without at our
  scale but the read dashboards will tell us when to add it (cache hit panels
  ship in the dashboards from day one).
- **Multi-tenancy**: if we ever want env-per-tenant or team tenants, flip
  `multitenancy_enabled` and add `X-Scope-OrgID` at the agents.
- ~~Alertmanager SPOF~~ — moved into the alert-extraction follow-up ticket
  (Mimir built-in HA alertmanager evaluation), see Scope changes at top.
- ~~Autoscaler query inventory~~ — resolved 2026-07-08: no autoscaler queries
  Prometheus; only Grafana datasources need repointing.
