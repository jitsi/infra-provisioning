# nomad/

Nomad jobspecs, one `.hcl` per service, and Nomad Packs in `jitsi_packs/packs/`. The matching
`scripts/deploy-nomad-*.sh` deploy them. Read the root `AGENTS.md` first for how those scripts are
called.

`CLAUDE.md` is a symlink to this file — edit this one.

## Prometheus alerts

- Built-in alert rules live in the `alerts.yml` template inside `prometheus.hcl`.
  `scripts/deploy-nomad-prometheus.sh` deploys one Prometheus job per datacenter
  (`prometheus-$ORACLE_REGION`), so every environment gets the same rules. Feature flags
  (`core_deployment`, `core_extended_services`, `production_alerts`, `autoscaler_alerts`,
  `environment_type`) gate some of them.
- A site adds its own rules through `prometheus_custom_alerts` in `sites/<env>/vars.yml`. The
  deploy script passes the value as `NOMAD_VAR_custom_alerts`, and the template appends it verbatim
  at the end of `alerts.yml`, inside the last rule group. Indent it to match the `- alert:` entries
  there.
- Give each rule `alert_url: ${replace(local.alert_url, "ALERTNAME", "<alert name>")}`. With
  `GRAFANA_BASE_URL` and `GRAFANA_DATASOURCE_UID` set, the link opens Grafana Explore on
  `ALERTS{alertname="<alert name>"}`. Without them, it falls back to the Prometheus alerts page.
  `datacenter` is an external label, so a template reads it as `$externalLabels.datacenter`.
  `$labels.datacenter` renders empty.
- Routing lives in `alertmanager.hcl` and keys on the `severity` label. `severe`, `warn` and
  `smoke` go to email. `severe` and `warn` also go to Slack. While a `severe` alert with the same
  `alertname` fires, the `warn` and `smoke` alerts are inhibited.
- A rule pages only when it has `severity: severe` and `page: true`, and the environment sets
  `ALERTMANAGER_PAGES_ENABLED=true` in its `stack-env.sh`. `deploy-nomad-alertmanager.sh` passes
  that flag as `pagerduty_enabled`, which defaults to `false`. Without the flag, the same rule still
  goes to Slack. With the flag, a `severe` rule without `page: true` shows in the Slack pages
  channel as a page candidate, but it does not reach PagerDuty.
- If a rule's metric does not exist in an environment, the rule returns no data and does not fire
  there. So a rule for a service that only some environments run is safe to add for all. The
  exception is `absent(...)`, which fires exactly when the metric is missing, and many built-in
  rules use it. Add an `absent()` rule only for a service that runs everywhere, or gate it with a
  feature flag.

## Periodic checks and probes

- **Prefer an in-cluster service for a resident check.** Write a `type = "service"` job (the
  cloudprober pattern). Deploy it per environment and region with `scripts/deploy-nomad-<x>.sh`,
  which the `provision-nomad-job` Jenkins job runs for `JOB_TYPE=<x>`. The service schedules itself,
  with a probe interval or an internal loop, and Jenkins does not re-trigger it. Register a Consul
  service, and add a `consul_sd_configs` scrape job for it to `prometheus.hcl`. The metrics and
  alerts then stay in the Prometheus of that environment. `opus-transcriber-proxy-monitor.hcl` is a
  small example.
- **The alternative is a Jenkins cron job.** A job with a `timed` trigger (see
  `jenkins/jobs/poll-signal-sidecar-release.yaml`) runs a script on the Jenkins agent. Such a script
  can emit a statsd gauge, as `scripts/synthetic-dialin-test.sh` does. The metric then comes from
  the agent, not from the target environment, and lands in the Prometheus that scrapes the agent's
  telegraf.
- **Statsd gauges do not persist.** The telegraf statsd input sets `delete_gauges = true`, both in
  `telegraf.hcl` and in the VM template in `infra-configuration`. So the gauge of a one-shot job
  disappears after the next flush. Do not build "N consecutive runs" PromQL on such a gauge. Put the
  retry or consecutive-failure logic in the job, and expose a persistent flag from a resident
  `/metrics` service. There is no Prometheus pushgateway.
  `Opus_Transcriber_Proxy_Monitor_Unhealthy` in `prometheus.hcl` uses this pattern.
