# Plan: Production-Grade Mimir Cluster to Replace Regional Prometheus

Status: IMPLEMENTED IN CODE (branch `JIT-16016-mimir-cluster`), NOT YET DEPLOYED.
Phases 0–5 are in the repo behind flags; rollout follows §9. Operations:
[mimir-runbook.md](mimir-runbook.md).
Tracking: JIT-16016 (this plan) / JIT-16017 (alert-catalog → ruler + Mimir HA alertmanager follow-up)
Author: generated 2026-07-08; risk review + fixes 2026-09-07 (see "Review" below)

## Pinned decisions (2026-07-08)

1. **Mimir version: `3.1.5`** (latest 3.1 patch; `3.1.2` was current when this
   was written, three patch releases followed, and `3.2.0` shipped 2026-08-19).
   Start on the latest 3.1 patch, move to 3.2 after the lonely soak via the
   normal N→N+1 path (3.2 turns on query sharding and remote execution by
   default — read its notes first). Mimir 3.x
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
   `cluster`/`__replica__` labels). **Correction (2026-09-07):** alloy already
   writes to the external 8x8 Mimir (`prometheus.remote_write "external"`,
   credentials in `secret/default/alloy/external-auth`) — that writer is
   reused; the `secret/default/prometheus/remote_write/<env_type>` secret is
   *not* moved. Scraped streams get their own HA-labelled writers (see Review
   R1/R2) and reach the external tenant in `primary` mode (one replica, no HA
   labels) until that tenant is confirmed to dedup on `cluster`/`__replica__`.
5. **Stable Mimir ring identity + rotation health gates.** Each group pins
   `-ingester.ring.instance-id=mimir-<N>` with `tokens_file_path` on its host
   volume, so consul-node rotations and alloc reschedules rejoin the ring as
   the *same* member (no unhealthy squatters, no token churn). The
   rotate-consul path gains Mimir/Loki-aware health gates (see §5a).

## Review (2026-09-07): risks found in the plan and how the implementation handles them

| # | Risk in the original plan | Fix (in code) |
|---|---|---|
| R1 | **HA tracker would drop OTLP and alloy self metrics.** Mimir decides per push *request* from the first series' labels: with `cluster`/`__replica__` as remote_write external labels, every OTLP-relayed stream (each client sends to ONE alloy, so half of them arrive via the non-elected replica) and both alloys' own metrics would be discarded as "non-elected replica"; mixed batches would be dropped wholesale or stored with a stray `__replica__`. | `alloy.hcl` has two writers per destination: `mimir` (OTLP + self, no HA labels) and `mimir_ha` (consul-SD scrape targets, `cluster`/`__replica__` as external labels). Separate components = separate WALs = never a mixed request. `limits.accept_ha_samples: true` (the plan omitted it — without it the labels are stored verbatim and every scraped series is doubled). |
| R2 | **External 8x8 Mimir tenant may not dedup.** "Only one alloy forwards until confirmed" is not expressible with two identical allocs. | `external_scrape_forward` = `primary` (default: only `NOMAD_ALLOC_INDEX` 0 forwards scraped streams, no HA labels; ~30 s gap on reschedule) / `ha` (both, with labels; enable only after the tenant is confirmed) / `none`. Implemented as a relabel gate in front of `prometheus.remote_write "external_ha"`. |
| R3 | **prometheus.hcl remote_write removal could drop scraped metrics from the external stack.** Alloy's external writer uses a *different* Vault secret than prometheus.hcl's; nothing proved they are the same tenant. | The removal (Phase 2 step 4) is **gated on confirming both secrets resolve to the same tenant/endpoint** (compare `endpoint`+`username` in `secret/default/prometheus/remote_write/<env_type>` with `<env_type>-01-oci-metrics-url`/`-username` in `secret/default/alloy/external-auth`). Until then prometheus.hcl keeps its remote_write; alloy's external_ha writer runs alongside. Mimir's HA tracker is irrelevant there because prometheus.hcl's streams carry no `cluster` label. |
| R4 | **Ingester restart loop.** The plan copied loki's `check_restart` (grace 60 s). A Mimir ingester replays its WAL before `/ready` goes 200; a large WAL takes minutes, so Nomad would kill it every minute forever. | `check_restart.grace = "10m"`, `healthy_deadline 10m`, `progress_deadline 15m`. |
| R5 | **Wrong 3.x config paths in the sketch.** `compactor.blocks_retention_period` and `ruler.alertmanager_url` are per-tenant limits in 3.x (`limits.compactor_blocks_retention_period`, `limits.ruler_alertmanager_client_config.alertmanager_url`); a `tokens_file_path` under a non-existent directory fails because Mimir does not create parent dirs; OCI S3-compat needs `bucket_lookup_type: path`. | Config written from the 3.1.5 configuration reference (`cmd/mimir/config-descriptor.json`); tokens files at the volume root (`/mimir/ingester-tokens`, `/mimir/store-gateway-tokens`); `bucket_lookup_type: path`; `query_scheduler.service_discovery_mode: ring` so all frontends see all schedulers; `usage_stats.enabled: false`; `activity_tracker.filepath` on the volume. |
| R6 | **Vault/consul-template `change_mode = restart` would bounce all three ingesters at once** on a credential rotation or on any alertmanager alloc move (the ruler URL is templated from consul). | Both `vault` and `template` use `change_mode = "noop"`; config and credential changes ship as a new job version, which rolls one zone at a time. Runbook documents the credential-rotation procedure. JIT-16017 must revisit the alertmanager target list (static render at alloc start). |
| R7 | **Rotation gates had a chicken-and-egg problem and no fail-closed behaviour.** The first consul rotation (the one that attaches the volumes) runs before mimir exists; a nomad API error must not read as "healthy". | `consul-metrics-health-gate.sh` skips a job that is *not deployed* (`No job(s) with prefix or ID`) but exits non-zero on any other nomad/API failure; pre-detach gate aborts before draining; post-attach gate replaces the blind sleep (also after pool c). `HEALTH_GATE=false` is the documented DR override. |
| R8 | **Memberlist port only half-opened.** The loki NSG rule is TCP-only; memberlist probes over UDP. | `consul_nsg_rule_mimir_gossip_tcp` + `_udp` for 7947; `memberlist.cluster_label = mimir-<dc>` so a stray loki/mimir packet is rejected rather than merging rings. |
| R9 | **Default limits would silently discard.** Mimir defaults: 150 k series, 10 k samples/s, 30 labels/series — below a region's telegraf fleet. | Job variables `max_global_series_per_user` (1 M), `ingestion_rate` (250 k/s), `ingestion_burst_size` (1 M), `max_label_names_per_series: 60`, `out_of_order_time_window: 5m`; overridable per env (`MIMIR_*` in stack-env.sh). Still not unlimited: the series cap is what protects 3 GB / 8 GB of ingester memory. |
| R10 | **`Mimir_Down` = `absent(up{job="mimir"})` would page every region that has no Mimir yet.** | Scrape job and `mimir_alerts` group are behind `var.mimir_alerts` (`PROMETHEUS_MIMIR_ALERTS=true` per environment). |
| R11 | **HA-tracker KV in consul assumed no ACLs; `custom_relabels` are Prometheus YAML, not Alloy.** | Phase 0 checklist gains "consul KV writable from consul nodes without token". Alloy takes `alloy_custom_relabel_rules` / `alloy_custom_external_labels` (Alloy syntax) from `config/vars.yml`, which lives in **infra-customizations-private** — that repo needs the companion edit (translation of the four `eght_component` rules, PR in that repo). |
| R13 | **Interface auto-detection would fail on OCI hosts.** Found by booting 3.1.5 against the rendered config: the 3.x querier has its own lifecycler, and any ring member without an explicit `instance_addr` auto-detects from interfaces `eth0`/`en0` and refuses to start when the NIC is named differently (OCI Ubuntu: `ens3`/`enp*`). | Every ring (`ingester`, `distributor`, `store_gateway`, `compactor`, `ruler`, `querier`, `query_scheduler`, `frontend.address`) gets `instance_addr` from `NOMAD_IP_grpc`. Config validated by starting Mimir 3.1.5 on it: strict-YAML parse clean, all modules initialise up to the object-storage sanity check (dummy creds). |
| R12 | **Memberlist `node_name` pinning would break rotations.** Pinning the gossip node name to `mimir-N` (tempting for symmetry with the ring id) makes the replacement node's join a "conflicting address" for the still-remembered dead member. | Only the *ring* `instance_id` is pinned; memberlist node names stay host-unique (hostname). `rejoin_interval: 1m` heals splits after DNS seeds move. |

Not changed by the review: monolithic mode, RF=3 + zone awareness, one bucket
with three prefixes, HA-dedup over Alloy clustering, Phase 3/6 deferral to
JIT-16017, the rollout order.

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
- Config template highlights (the real thing is the job file; paths are 3.x):

```yaml
target: all
multitenancy_enabled: false
usage_stats: { enabled: false }
activity_tracker: { filepath: /mimir/metrics-activity.log }
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
      bucket_lookup_type: path            # OCI needs path-style
      access_key_id / secret_access_key:  {{ with secret "secret/default/mimir/s3" }}
blocks_storage:
  storage_prefix: blocks
  tsdb: { dir: /mimir/tsdb }              # host volume
  bucket_store: { sync_dir: /mimir/tsdb-sync }
ruler_storage:        { storage_prefix: ruler }
alertmanager_storage: { storage_prefix: alertmanager }
memberlist:
  cluster_label: mimir-<dc>               # never merge with loki's ring
  bind_port / advertise_port: 7947
  advertise_addr: {{ env "NOMAD_IP_gossip" }}
  rejoin_interval: 1m
  join_members: [<dc>-consul-{a,b,c}.<zone>:7947]
ingester:
  ring:
    replication_factor: 3
    zone_awareness_enabled: true
    instance_availability_zone: zone-${group.key}
    instance_id: mimir-${group.key}       # stable identity across node rotations
    tokens_file_path: /mimir/ingester-tokens   # volume ROOT: mimir won't mkdir
    unregister_on_shutdown: false         # rolling restarts don't reshard
distributor:
  ha_tracker:
    enable_ha_tracker: true
    kvstore: { store: consul, prefix: mimir/ha-tracker/, consul: { host: <node>:8500 } }
store_gateway:
  sharding_ring: { replication_factor: 3, zone_awareness_enabled: true,
                   instance_id: mimir-${group.key}, tokens_file_path: /mimir/store-gateway-tokens,
                   unregister_on_shutdown: false, wait_stability_min_duration: 1m }
compactor: { data_dir: /mimir/compactor, sharding_ring: { instance_id: mimir-${group.key} } }
ruler:     { rule_path: /mimir/ruler,    ring:          { instance_id: mimir-${group.key} } }
querier:   { ring: { instance_id: mimir-${group.key}, instance_addr: <NOMAD_IP_grpc> } }  # R13
query_scheduler: { service_discovery_mode: ring, ring: { instance_id: mimir-${group.key} } }
limits:
  accept_ha_samples: true                 # REQUIRED for the HA tracker to act
  ha_cluster_label: cluster
  ha_replica_label: __replica__
  max_global_series_per_user: ${var.max_global_series_per_user}   # 1M default
  ingestion_rate: ${var.ingestion_rate}                           # 250k/s
  ingestion_burst_size: ${var.ingestion_burst_size}
  max_label_names_per_series: 60
  out_of_order_time_window: 5m            # tolerate agent replay after restarts
  compactor_blocks_retention_period: ${var.retention_period}      # 2160h/90d
  ruler_alertmanager_client_config:
    alertmanager_url: {{ range service "alertmanager" }}http://addr:port,{{ end }}
```

- `update` stanza (zero-downtime rolling — see §5).
- Service `mimir` with `int-urlprefix-${var.mimir_hostname}/` tag, health check
  `GET /ready`, `check_restart` with **`grace = "10m"`** (not loki's 60 s: WAL
  replay must finish before `/ready` is 200, see Review R4).
- `vault { change_mode = "noop" }` and template `change_mode = "noop"` (Review R6).
- Resources `%{ if prod }2000 MHz / 8 GB%{ else }1000 MHz / 3 GB%{ endif }`.

`scripts/deploy-nomad-mimir.sh` — copy of deploy-nomad-loki.sh minus the
ansible-vault credential lookup (creds come from Vault inside the job): renders
`[JOB_NAME]` → `mimir-$ORACLE_REGION`, exports hostname/namespace/env-type and
the optional `MIMIR_VERSION` / `MIMIR_RETENTION_PERIOD` /
`MIMIR_MAX_GLOBAL_SERIES` / `MIMIR_INGESTION_RATE` / `MIMIR_INGESTION_BURST_SIZE`
overrides, runs the job, then `create-oracle-cname-stack.sh` for
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

All of it is behind job variables set from the environment's stack-env.sh by
`deploy-nomad-alloy.sh`: `ALLOY_ENABLE_MIMIR_WRITE` (default false),
`ALLOY_ENABLE_SCRAPE` (false), `ALLOY_ENABLE_LEGACY_PROMETHEUS_WRITE` (true),
`ALLOY_EXTERNAL_SCRAPE_FORWARD` (`primary`). Rendered configs for every switch
combination were validated with `alloy validate` (3.x image) before merge.

1. **Scrape components** (`enable_scrape`): a `discovery.consul` +
   `prometheus.scrape` + `prometheus.relabel` trio per job, generated from a
   `scrape_jobs` map — `alertmanager` (15s), `cloudprober` (10s), `telegraf`
   (30s), `opus-transcriber-proxy-monitor` (30s), `gitea-mirror` (60s), **plus
   the new `mimir` job** (15s) — with the same `service` metric-relabels as
   prometheus.hcl, then a shared `scrape_common` relabel that appends
   `alloy_custom_relabel_rules` (Alloy-syntax translation of
   `prometheus_custom_relabels`, from config/vars.yml). Alloy's own metrics
   keep the existing `integrations/self` job.
2. **Labels for HA dedup — on separate writers (Review R1)**: the shared scrape
   targets go to `prometheus.remote_write "mimir_ha"` whose `external_labels`
   carry `datacenter/environment/region` plus `cluster: <env>-<region>` and
   `__replica__: alloy-<NOMAD_ALLOC_INDEX>`; OTLP relays and self metrics go
   to `prometheus.remote_write "mimir"` with the same labels **minus** the HA
   pair. Mimir gets `accept_ha_samples: true`.
3. **Write destinations**: (a) the local Mimir at
   `https://<env>-<region>-mimir.<tld>/api/v1/push` (`enable_mimir_write`),
   (b) the legacy prometheus remote-write receiver (`enable_legacy_prometheus_write`,
   OTLP streams only, kept during the soak, off at Phase 5), (c) the **existing**
   `prometheus.remote_write "external"` (OTLP + self) and the new
   `external_ha` for scraped streams, both from `secret/default/alloy/external-auth`.
   The external_ha path runs in `primary` mode (only alloc index 0 forwards, no
   HA labels) until the external tenant's HA dedup is confirmed, then `ha`
   (Review R2).
4. **prometheus.hcl loses its `remote_write` block once R3 is confirmed** — i.e.
   once the two Vault secrets are shown to address the same external tenant.
   Then old prometheus is a purely local scrape-and-evaluate alert engine
   until the ruler ticket retires it. (Not done in this branch: it is a
   one-line deletion gated on that check.)
5. **Resources**: alloy task bumped from 256 MHz / 512 MB to 512 MHz / 1.5 GB
   (up to four remote-write WALs); calibrate with the alloy-monitor dashboard's
   new remote-write and scrape rows.

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
this plan, added to the existing prometheus.hcl alert template (a
`mimir_alerts` group) plus a consul-SD scrape job for the `mimir` service in
prometheus.hcl, both behind `var.mimir_alerts` (`PROMETHEUS_MIMIR_ALERTS=true`
in the environment's stack-env.sh once Mimir is deployed there — Review R10),
so the current evaluator watches the new cluster from day one. They migrate to
the ruler with everything else later.

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
3. **Post-attach gate** (`scripts/consul-metrics-health-gate.sh post`, called
   from `rotate-consul-oracle.sh` in place of the blind sleep, after every
   pool including c): poll until (a) 3 mimir-N / loki-N allocs are running,
   (b) `/ready` returns 200 three times in a row through Fabio, (c) the
   ingester ring (`/ingester/ring`, JSON via `Accept: application/json`) is
   3 ACTIVE / 0 not-active, (d) same for loki `/ready` + `/ring`. Timeout
   default 15m; on timeout the pipeline **fails loudly** rather than rolling on
   to the next pool. A job that is not deployed in the region is skipped
   (first rotation, before mimir exists); a nomad API failure fails closed
   (Review R7).
4. **Jenkinsfile**: `HEALTH_GATE` (default `true`; escape hatch for disaster
   recovery when the gate can never pass) and `HEALTH_GATE_TIMEOUT_MINUTES`
   (15) parameters on `rotate-consul`; the gate echoes what it is waiting on.

## 6. Monitoring the monitor

### Self-metrics

The Alloy pair scrapes each Mimir instance's `/metrics` (job `mimir`) and its
own `/metrics` (job `alloy`), writing to both the local Mimir and the external
8x8-hosted Mimir. Sending Mimir's own health metrics to the **external** stack
solves "who watches the watcher": if the regional Mimir is down, its absence
still alerts from the external stack (mirrors the existing global-alertmanager
design).

### New alert rules (`mimir_alerts` group in prometheus.hcl, behind `var.mimir_alerts`; migrating to the ruler with the follow-up ticket; starred ones also reach the external stack through alloy)

| Alert | Expr (as implemented) | Severity |
|---|---|---|
| *Mimir_Down | `absent(up{job="mimir"})` 5m | severe |
| Mimir_Instance_Down | `count(up{job="mimir"} == 1) < 3` | warn (5m) / severe (30m) |
| Mimir_Ring_Unhealthy | `max(cortex_ring_members{job="mimir", state="Unhealthy"}) > 0` 5m | severe |
| Mimir_Ingestion_Discards | `sum by (reason) (rate(cortex_discarded_samples_total[5m])) > 10` 15m | warn |
| Mimir_HA_Dedup_Flapping | `sum(increase(cortex_ha_tracker_elected_replica_changes_total[10m])) > 3` 15m | smoke |
| Mimir_Compactor_Stalled | `time() - max(cortex_compactor_last_successful_run_timestamp_seconds) > 4h` (guarded by `> 0`) | warn (4h) / severe (24h) |
| Mimir_StoreGateway_Sync_Failing | `sum(rate(cortex_bucket_stores_blocks_sync_failures_total[10m])) > 0` 15m | warn |
| Mimir_Object_Storage_Errors | failure ratio per `operation` > 5% for 15m | warn |
| Mimir_Query_Latency_High | p99 `cortex_request_duration_seconds` route `prometheus_api_v1_query.*` > 10s | warn |
| Mimir_Write_Latency_High | p99 route `api_v1_push.*` > 2.5s (mixin threshold; 1s was noise-prone) | warn |
| Mimir_Ruler_Failing | `sum(rate(cortex_prometheus_rule_evaluation_failures_total[5m])) > 0` 10m | severe (rule evals ARE our alerting) |
| *Alloy_Scrape_Down | `count(up{job="integrations/self", alloy_type="internal"} == 1) < 2` 10m (alloy's existing self job, not a new `alloy` job) | severe |
| Alloy_RemoteWrite_Backlog | highest ts − highest sent ts `> 120s` per (instance, component_id, url) for 10m | warn |
| Mimir_Memory_High | existing Nomad_Job_Memory_Use_High covers it — mimir is deliberately NOT added to the `task!~"prometheus"` exclusion |

`job="mimir"` requires the prometheus.hcl `mimir` scrape job (same flag). In
nonprod `severe` is downgraded to `warn` by the existing relabel.

Also: a **cloudprober http probe** `mimir` against `https://<mimir_hostname>/ready`
and a synthetic **query probe** `mimir-query` (instant query `vector(1)` via
`/prometheus/api/v1/query`, validated on 2xx + `"status":"success"`) — end-to-end
read-path checking. Both in the `jitsi_cloudprober` pack behind `enable_mimir`
(`CLOUDPROBER_ENABLE_MIMIR=true` in stack-env.sh).

### Grafana dashboards (new JSONs in `grafana/dashboards/`)

Hand-built from the mimir-mixin's key queries, trimmed to single-tenant
monolithic reality (no jsonnet toolchain in this repo), following the style of
the existing `alloy-monitor.json` (datasource / environment / region variables,
`job="mimir"` selector, cross-linked via the `mimir` tag):

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
- [ ] **Consul KV writable** from the consul nodes without an ACL token (HA
  tracker state lives at `mimir/ha-tracker/`); **Vault policy** for nomad
  workloads covers `secret/default/mimir/s3` (tempo's `secret/default/tempo/s3`
  works the same way, so this should already hold).
- [ ] **External tenant HA dedup confirmed** before switching
  `ALLOY_EXTERNAL_SCRAPE_FORWARD` from `primary` to `ha`; **same-tenant check**
  of the two Vault secrets before deleting prometheus.hcl's `remote_write`
  (Review R2/R3).
- [ ] **Bucket security**: dedicated S3 credential (`secret/default/mimir/s3`),
  scoped IAM policy to only the mimir bucket (follow the ops-repo-test
  compartment/IAM lessons), no versioning (compactor churns objects),
  no lifecycle rule (compactor owns deletes).
- [x] **Gossip port 7947** allowed in the consul NSG, TCP **and UDP**
  (`consul_nsg_rule_mimir_gossip_*` in terraform/consul-server; applied on the
  next consul-server terraform run, which the volume-attaching rotation does).
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

| File | Action | Status |
|---|---|---|
| `nomad/mimir-cluster.hcl` | NEW — 3-group monolithic Mimir cluster | done |
| `nomad/alloy.hcl` | EDIT — consul-SD scrape components, split direct/HA writers to local mimir + external 8x8 mimir, external forward modes, resource bump | done (flags default off) |
| `nomad/prometheus.hcl` | EDIT — `mimir` scrape job + `mimir_alerts` group behind `var.mimir_alerts`; `remote_write` deletion gated on R3; DELETE job in Phase 6 | done |
| `scripts/deploy-nomad-mimir.sh` | NEW — job deploy + CNAME (`mimirtool rules sync` added by follow-up ticket) | done |
| `scripts/deploy-nomad-alloy.sh` / `deploy-nomad-prometheus.sh` / `deploy-nomad-cloudprober.sh` | EDIT — env flags (`ALLOY_*`, `PROMETHEUS_MIMIR_ALERTS`, `CLOUDPROBER_ENABLE_MIMIR`) | done |
| `scripts/consul-metrics-health-gate.sh` | NEW — pre/post rotation gate | done |
| `scripts/rotate-consul-oracle.sh`, `rotate-consul-pre-detach.sh`, `jenkins/groovy/rotate-consul/Jenkinsfile`, `jenkins/jobs/rotate-consul.yaml` | EDIT — gates replace the blind sleep; `HEALTH_GATE*` params | done |
| `scripts/create-buckets-oracle.sh` | EDIT — add `mimir-$ENVIRONMENT` bucket | done |
| `terraform/volumes-mimir/` | NEW — 3× 100 GB block volumes, consul role, indexed | done |
| `terraform/consul-server/create-consul-server-oracle.tf` | EDIT — NSG rules 7947 tcp+udp | done |
| `nomad/jitsi_packs/packs/jitsi_cloudprober` | EDIT — `enable_mimir` probes | done |
| `jenkins/jobs/provision-nomad-mimir.yaml` | NEW (generic provision-nomad-job Jenkinsfile) | done |
| `jenkins/jobs/release-nomad-mimir.yaml` + `jenkins/groovy/release-nomad-mimir/Jenkinsfile` | NEW — clone of release-nomad-prometheus | done |
| `grafana/dashboards/mimir-*.json` (×4) | NEW; `alloy-monitor.json` EDIT (scrape + per-endpoint remote-write rows) | done |
| `doc/mimir-runbook.md` | NEW | done |
| **infra-customizations-private** `config/vars.yml` | EDIT — add `alloy_custom_relabel_rules` / `alloy_custom_external_labels` (Alloy translation of the `eght_*` relabels; see deploy-nomad-alloy.sh) | **companion PR needed** |
| **infra-customizations-private** `sites/*/stack-env.sh` | EDIT per env at each phase: `ALLOY_ENABLE_MIMIR_WRITE`, `ALLOY_ENABLE_SCRAPE`, `PROMETHEUS_MIMIR_ALERTS`, `CLOUDPROBER_ENABLE_MIMIR`, later `ALLOY_ENABLE_LEGACY_PROMETHEUS_WRITE=false`; optional `MIMIR_*` sizing | **companion PR per env** |
| Vault `secret/default/mimir/s3` | mint per environment before first deploy | manual |

## 9. Rollout order

0. Prereqs per environment: apply `terraform/volumes-mimir`, run
   `create-buckets-oracle.sh`, mint `secret/default/mimir/s3`, then rotate the
   consul pool (attaches volumes, applies the 7947 NSG rules; the new gates
   skip mimir because it is not deployed yet).
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
