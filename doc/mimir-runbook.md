# Mimir cluster runbook

Operations guide for the per-region Grafana Mimir cluster
([nomad/mimir-cluster.hcl](../nomad/mimir-cluster.hcl)). Design and rollout
plan: [mimir-cluster-plan.md](mimir-cluster-plan.md). Ticket: JIT-16016.

## What is running

| Thing | Where |
|---|---|
| Job | `mimir-<region>` in each Nomad DC; groups `mimir-0/1/2`, one per consul node |
| Image | `grafana/mimir:<mimir_version>` (default in mimir-cluster.hcl), monolithic `-target=all` |
| Ring identity | `mimir-N` with tokens in `/mimir/ingester-tokens` and `/mimir/store-gateway-tokens` on the host volume |
| Host volume | `mimir-N` = OCI block volume tagged `volume-type=mimir volume-role=consul volume-index=N` (terraform/volumes-mimir), mounted at `/mnt/bv/mimir-N` |
| Object storage | bucket `mimir-<environment>` in the region, prefixes `blocks/`, `ruler/`, `alertmanager/` |
| Credentials | Vault kv `secret/default/mimir/s3` (`access_key`, `secret_key`), read by the job template |
| Gossip | memberlist on static **7947**/tcp+udp between consul nodes (loki uses 7946) |
| HA dedup state | consul KV `mimir/ha-tracker/` on the local consul cluster |
| Endpoints | `https://<env>-<region>-mimir.<tld>` via Fabio: `/api/v1/push` (write), `/prometheus/*` (query API, Grafana datasource), `/ready`, `/ingester/ring`, `/store-gateway/ring`, `/compactor/ring`, `/distributor/ha-tracker` |
| Deploy | `scripts/deploy-nomad-mimir.sh`; Jenkins `provision-nomad-mimir` (one region) / `release-nomad-mimir` (all regions, governance) |
| Writers | the two `alloy-<region>` allocs only (nomad/alloy.hcl). Nothing else remote-writes to Mimir |
| Alerts | `mimir_alerts` group in prometheus.hcl (enabled with `PROMETHEUS_MIMIR_ALERTS=true`), cloudprober `mimir` + `mimir-query` probes |
| Dashboards | grafana/dashboards/mimir-overview, mimir-writes, mimir-reads, mimir-ruler-compactor, alloy-monitor |

Handy commands (from the repo root, `ENVIRONMENT`/`ORACLE_REGION` set):

```bash
export NOMAD_ADDR=https://$ENVIRONMENT-<local-region>-nomad.jitsi.net
nomad job status mimir-$ORACLE_REGION
nomad alloc logs -stderr -f <alloc>                    # mimir logs at warn level
H=https://$ENVIRONMENT-$ORACLE_REGION-mimir.jitsi.net
curl -s $H/ready
curl -s -H 'Accept: application/json' $H/ingester/ring | jq '.shards[] | {id,state,zone,address}'
curl -s -H 'Accept: application/json' $H/store-gateway/ring | jq '.shards[] | {id,state}'
curl -s "$H/prometheus/api/v1/query?query=count(up)"
scripts/consul-metrics-health-gate.sh pre               # the same check the consul rotation runs
```

## Healthy looks like

- `nomad job status mimir-<region>`: 3 running allocs, one per consul node.
- `/ingester/ring` and `/store-gateway/ring`: exactly 3 members `mimir-0/1/2`,
  all `ACTIVE`, zones `zone-0/1/2`, no `Unhealthy`.
- `/ready` returns 200 from every instance (curl the Fabio hostname a few times).
- `mimir-overview` dashboard: ingestion rate steady, discarded samples ~0,
  compactor last successful run < 2h ago, object-storage error rate 0.
- `/distributor/ha-tracker`: one elected replica (`alloy-0` or `alloy-1`) per
  cluster `<env>-<region>`, elected timestamp changing rarely.

## Rolling restart / config change / version bump

Every change is a Nomad job update; the `update` stanza rolls one group (= one
zone) at a time with `auto_revert`. Do not `nomad alloc stop` more than one
mimir alloc at once: RF=3 needs 2 of 3 ingesters for writes.

1. Change `nomad/mimir-cluster.hcl` (or bump `mimir_version`).
2. Deploy to **lonely** first: Jenkins `provision-nomad-mimir` with
   `ENVIRONMENT=lonely`. Watch `nomad job status` until all three groups have
   rolled and the ring is 3/3 ACTIVE.
3. Watch the `mimir-overview` / `mimir-writes` dashboards for discards, ring
   health and write latency for at least one compaction cycle (2h).
4. Roll other environments with `release-nomad-mimir` (region by region,
   governance ticket for prod).

Version bumps: Mimir supports N to N+1 minor upgrades only; never skip a minor
version. Read the release notes for removed flags first (3.1 removed several
2.x-era flags; the config template is validated against 3.x). For a breaking
config change, ship a config compatible with both versions first, then the
image.

An ingester restart replays its WAL before `/ready` goes 200. The health
check's `check_restart` grace is 10 minutes; if an instance legitimately needs
longer (very large WAL), do not shorten it, fix the WAL size (see "Volume
full").

## Consul node rotation

`rotate-consul` (Jenkins) rotates pools a, b, c in sequence. Each rotation moves
the node's `mimir-N` alloc to the replacement node, which attaches the same
`mimir-N` volume, replays the WAL and rejoins the ring **as the same member**
(`instance_id: mimir-N`, tokens file on the volume). No manual ring action is
needed in the happy path.

The pipeline is gated by `scripts/consul-metrics-health-gate.sh`:

- before draining a node (`pre`): refuses to start if mimir or loki are not 3/3
  ACTIVE with `/ready` 200;
- after each pool (`post`): waits (default 15 min, `HEALTH_GATE_TIMEOUT_MINUTES`)
  for the new node's mimir/loki allocs to be running and the rings back to
  3/3, and **fails the build** instead of rotating the next pool on timeout.

Both gates skip a job that is not deployed in the region (the first rotation,
which attaches the volumes, runs before mimir exists). `HEALTH_GATE=false` is
the escape hatch for disaster recovery only.

If the post gate times out:

1. `nomad job status mimir-<region>`: is `mimir-N` running on the new node? If
   pending with "missing host volume", the volume did not attach/mount. Check
   the node's `/mnt/bv/`, `oci bv volume list` for the `mimir-N` volume's
   attachment state, and re-run `terraform/consul-server` for the pool.
2. If running but not ready: `nomad alloc logs`. WAL replay of a big ingester
   can take minutes; ring membership problems show as gossip/join errors
   (check 7947 is open in the consul NSG).
3. Fix, re-run the gate by hand (`consul-metrics-health-gate.sh post`), then
   re-run the rotation job for the remaining pools.

## Replacing a failed volume or instance

Symptom: `Mimir_Instance_Down` for a long time, alloc pending on a missing host
volume, or a volume in a failed state in OCI.

1. Confirm the other two ingesters are ACTIVE (writes and reads are still
   served; there is no rush that justifies touching a second instance).
2. Recreate the volume: `terraform/volumes-mimir/create-volumes-mimir-oracle.sh`
   after removing the dead volume from state (`ACTION=... terraform state rm`
   or taint the `mimir-volume[N]` resource). Same tags, same index.
3. Rotate or re-run the consul node for that pool so the new volume is attached
   and mounted (`rotate-consul` with the other pools already healthy, or
   `scripts/remount-boot-volumes.sh`).
4. The new `mimir-N` starts with an empty volume: it generates fresh tokens and
   joins with the same instance id. Ring members with the same id are replaced,
   so no `forget` is needed. Its historical blocks are in the bucket; only the
   un-shipped head (up to 2h) of that replica is lost, and RF=3 means the other
   two replicas hold that data.
5. Expect a short window where the ring shows `mimir-N` as `JOINING` /
   `Unhealthy`; if the old member never leaves (only when the id changed),
   forget it: `/ingester/ring` page has a **Forget** button per member (POST
   `forget=<id>`), same on `/store-gateway/ring`.

## Compactor stuck (`Mimir_Compactor_Stalled`)

The three compactors shard work over a ring; any one can run each job.

1. `mimir-ruler-compactor` dashboard: last successful run, runs failed, blocks
   marked for deletion.
2. Logs (`grep -i compactor`): the usual causes are object-storage errors
   (credentials, bucket permissions, OCI throttling) or a corrupt block.
3. For a corrupt block the log names the block ID; mark it for no-compaction:
   `mimirtool backfill`/`mimirtool bucket-validation` are not needed, use
   `curl -XPOST $H/compactor/delete_tenant` only if the whole tenant must go
   (it must not). Preferred: `mark-blocks -mark-type no-compact` from the Mimir
   tools image against the `blocks/` prefix, then let the next run continue.
4. If the compactor ring itself is unhealthy, it heals with the ingester ring
   (same memberlist); restart the affected group via a normal rolling deploy.

## Ingestion discards (`Mimir_Ingestion_Discards`)

`reason` label tells you which limit: `per_user_series_limit`
(`max_global_series_per_user`), `rate_limited` (`ingestion_rate` /
`ingestion_burst_size`), `max_label_names_per_series`, `sample_out_of_order`
(> 5 min late), `sample_too_old`. Limits are job variables
(`MIMIR_MAX_GLOBAL_SERIES`, `MIMIR_INGESTION_RATE`, `MIMIR_INGESTION_BURST_SIZE`
in the environment's stack-env.sh); raise deliberately, and check the ingester
memory headroom on `mimir-overview` first (every ingester holds every series).

## HA dedup problems

- Both alloy replicas' scraped series appear doubled (two `__replica__` values
  for the same target): `accept_ha_samples` is off or the scraped streams went
  through the non-HA writer. Check `limits.accept_ha_samples: true` in the
  rendered config and that scrape jobs forward to `prometheus.remote_write.mimir_ha`.
- Scraped metrics have gaps every time an alloy restarts: expected up to the HA
  failover timeout (30s). Longer gaps: `Mimir_HA_Dedup_Flapping`, look at the
  `/distributor/ha-tracker` page and alloy remote-write lag.
- OTLP-relayed or alloy self metrics disappear intermittently: they were sent
  through an HA writer. They must stay on `prometheus.remote_write.mimir`.

## Object storage credential rotation

1. Mint the new key pair for the mimir bucket user in OCI, write it to Vault
   `secret/default/mimir/s3` (`access_key`, `secret_key`).
2. The job uses `vault { change_mode = "noop" }` and a `noop` template on
   purpose (a credential change must not restart all three ingesters at once),
   so roll it in with a normal deploy: `provision-nomad-mimir` for the region.
   The template re-reads the secret on each new alloc, one group at a time.
3. Verify block uploads resume (`thanos_objstore_bucket_operation_failures_total`
   back to 0, `mimir-overview` object-storage panel), then revoke the old key.

## Volume full

100 GB per instance holds the WAL, the 2h head block and compactor scratch.
Growth means blocks are not shipping (object storage errors) or compaction
scratch is not being cleaned. Fix the upload problem first; blocks ship within a
minute once the bucket is reachable and the local retention
(`blocks_storage.tsdb.retention_period`, 13h default) removes them. Never delete
files under `/mimir/tsdb` by hand while the ingester runs.

## Disaster recovery: rebuild a region from the bucket

Blocks in the bucket are the source of truth; the volumes hold at most ~2h of
un-shipped data plus tokens.

1. Recreate volumes (terraform/volumes-mimir) and the consul nodes as needed.
2. Deploy the job. New instances register as `mimir-0/1/2`, store-gateways sync
   index headers from `blocks/`, queries work as soon as `/ready` is 200.
3. The lost window is what was in the ingesters and not yet shipped, at most
   2h. Alloy's WAL re-sends what it still holds; the external 8x8 Mimir has a
   full copy of the scraped and OTLP streams for anything older.
4. Ring members from the dead cluster that were never unregistered show as
   `Unhealthy` only if their ids differ; with the fixed ids they are simply
   replaced.

## Rollback to the old prometheus (during migration)

Until Phase 6 of the plan, `prometheus-<region>` is still running and scraping.
To fall back for queries, switch the Grafana datasource back to
`https://<env>-<region>-prometheus.<tld>`; to fall back for the external feed,
redeploy alloy with `ALLOY_EXTERNAL_SCRAPE_FORWARD=none` and prometheus.hcl
with its `remote_write` block (git history, Phase 2 commit). Metrics written only
to Mimir during the window stay in Mimir.
