# Autoscaler: don't count a booting jibri as unavailable

A ready-to-use task prompt for a change in [jitsi-autoscaler](https://github.com/jitsi/jitsi-autoscaler).
It is kept here, next to the jibri boot playbook work that exposed the problem, so it can be
picked up later. Paste everything below the line into a coding session opened in a
jitsi-autoscaler checkout.

---

Work in the jitsi-autoscaler repo (github.com/jitsi/jitsi-autoscaler). Branch from an up-to-date origin/main.

## Problem

A jibri instance that has launched but whose jibri is not up yet can make the autoscaler launch a second instance. The first instance then reaches healthy, the group has one idle jibri too many, and the autoscaler scales one down. Each slow boot costs an extra instance plus the churn.

Here is what happened in stage-8x8 eu-frankfurt-1 on 2026-09-27 (group `stage-8x8-eu-frankfurt-1-JibriCustomGroup`, desired 1, all times UTC):

- 13:49:56: the autoscaler launched instance A.
- 13:58:46: the sidecar on A started. Jibri was not running yet, so the sidecar's stats call to `http://localhost:2222/jibri/api/v1.0/health` got ECONNREFUSED, and it reported an empty stats report ("Empty stats, error occurred, returning blank report").
- 13:59:56: the autoscaler launched instance B, 70 seconds after A's first empty report.
- 14:10:07: jibri on A reported HEALTHY/IDLE.
- 14:21:03: the autoscaler sent A a shutdown command as a scale-down.

## Why it happens (read the code to confirm; line numbers are from b711dc8)

1. `cloud_manager.ts` (~L58) tracks a new instance with `status: { provisioning: true }` and `timestamp: Date.now()`.
2. `InstanceTracker.stats()` (`instance_tracker.ts` ~L77) builds a brand-new state with `status: { provisioning: false }` from every sidecar report. When `report.stats` is empty or `report.statsError` is set, it logs "Empty stats report" and leaves `jibriStatus` unset. The instance is no longer provisioning.
3. Further down in `stats()` (~L200-L212), a metric is stored for any instance that is not provisioning and not shutting down. For jibri, sip-jibri and availability groups the value is 1 only when `jibriStatus.busyStatus == Idle`. Otherwise it is 0 ("If Jibri is not up, the available metric is tracked with value 0").
4. `autoscaler.ts` `scaleUpChoice()` (~L320) scales jibri groups up when the available value is below `scaleUpThreshold`. So a booting jibri counts as an unavailable jibri.
5. If the sidecar has not reported at all, the group has no metrics and the autoscaler logs "No metrics available, no desired count adjustments possible" (~L290). A silent booting instance does not cause this. An instance reporting empty stats does.

## Change wanted

For jibri, sip-jibri and availability instance types: treat a stats report that carries no jibri status (empty stats, or `statsError`) as still provisioning if the instance is inside its provisioning window. That means:

- Keep `status.provisioning = true` in the saved state.
- Write no availability metric for it (the same as for a launch-tracked provisioning instance).

After the window, keep today's behaviour: provisioning false, metric 0. A jibri that never comes up must still count as unavailable, so it gets replaced and does not block scaling forever.

JVB, jigasi, nomad and the other stress-based types already skip the metric when stats are missing (`trackMetric = false`). Leave them alone unless you find they share the bug.

## The pitfall to design around

Provisioning expiry (`instance_state_expiry.ts` `partitionExpiredStates`, used by both RedisStore and ConsulStore) measures `provisioningTTL` from `state.timestamp`. Every sidecar report refreshes `timestamp`. If `stats()` simply kept `provisioning: true` on empty reports, a jibri that never comes up would stay "provisioning" indefinitely, because each report resets the clock.

The window therefore needs a stable start time that survives reports, and it must not be the report timestamp. Options, pick one and justify it:

- Carry a launch timestamp in the state: set it in `cloud_manager.ts` at launch, and have `stats()` copy it forward from the previously stored state.
- Look up the launch time from the audit launch event (`audit.saveLaunchEvent`).
- Use a launch or creation time the sidecar report already carries, if one exists (check `StatsReport` and `report.instance`).

Use the existing `provisioningTTL` (`PROVISIONING_TTL_SEC`, default 900 s) as the window unless there is a reason not to. Be careful with instances that were never launch-tracked, for example ones created outside the autoscaler or present before a restart. With no known launch time, fall back to today's behaviour.

Also check anything else that reads `status.provisioning` and would now see it true for longer:

- `instance_launcher.ts` `getProvisioningOrWithoutStatusInstances` / `getRunningInstances`, and the scale-down candidate selection, so a booting instance is not picked for scale-down in preference to an idle one.
- `group_report.ts`.
- Anything that counts provisioning instances toward the desired count.

## Done means

- Unit tests in `src/test/` that cover:
  - An empty report inside the window stays provisioning with no metric.
  - An empty report after the window becomes provisioning false with metric 0.
  - A report with an Idle jibriStatus inside the window becomes provisioning false with metric 1, so a jibri that comes up early is counted immediately.
  - A report for an instance with no known launch time keeps today's behaviour.
  - A JVB/stress instance is unchanged.
- `npm test` and `npm run lint` pass. Say in the PR what you ran.
- The PR description explains the behaviour change in terms someone with only the repo can follow, including the scenario above. Do not put ticket keys (JIT-..., RP-...) in the branch name, commits or PR text: the repo is public.

For context, infra-configuration is changing separately (jitsi/infra-configuration#982) so the jibri boot playbook starts the sidecar only after jibri reports healthy. That removes the trigger for jibri VMs booted by that playbook. This autoscaler change is the general fix: it covers every sidecar and image, including ones that start the sidecar early.
