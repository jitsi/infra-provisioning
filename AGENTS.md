# infra-provisioning

Provisioning and deployment for the Jitsi cloud infrastructure: Terraform stacks, Nomad jobspecs,
Packer image builds, and the shell scripts and Jenkins jobs that drive them. Almost everything
targets OCI. The AWS pieces that remain are legacy.

`CLAUDE.md` is a symlink to this file — edit this one.

This repository is public. The tracker the team plans work in is not.

## Do not reference tickets in anything that lands here

Never put a ticket key (`JIT-…`, `RP-…`) or a tracker URL in:

- branch names
- commit messages
- PR titles, descriptions, or review comments
- code comments, config, or docs in the tree

To anyone outside the company — which is most people reading this repo — a bare ticket key is an
identifier they cannot resolve, standing in for the explanation they actually needed. Write the
explanation instead: what changed, and why, in terms someone with only the repo in front of them
can follow. Name branches after the change (`telegraf-namedrop-fix`), not the ticket.

Link in the other direction: the ticket gets a comment with the PR URL, the PR says nothing about
the ticket. Older history contains keys from before this rule; leave them alone.

(The `RP_TICKET` job parameter in `jenkins/jobs/` is a different thing — a runtime input to a
deploy, not a reference baked into the tree.)

## Layout

| Path | What's in it |
| --- | --- |
| `scripts/` | The entry points. Bash, with a few Python helpers. Naming is by verb: `create-*`, `deploy-*`, `rotate-*`, `delete-*`, `check-*`, `set-*`, `build-*`, `aggregate-*`. |
| `terraform/<stack>/` | One directory per stack, each with a `<stack>-stack.tf` and a `create-…-stack.sh` wrapper that assembles the backend config and variables. There are no shared Terraform modules — each stack is flat. `terraform/lib/` is unrelated: shell libraries (`postinstall-*.sh`) that get assembled into instance user-data. |
| `nomad/` | Jobspecs, one `.hcl` per service, deployed by the matching `scripts/deploy-nomad-*.sh`. `nomad/jitsi_packs/packs/` holds Nomad Packs for the bigger services (`jitsi_meet_backend`, `jitsi_meet_jvb`, `jitsi_autoscaler`, …). |
| `jenkins/jobs/` | Job definitions as Jenkins Job Builder YAML. |
| `jenkins/groovy/<job>/Jenkinsfile` | The pipeline each job runs. `Utils.groovy` and `GovernanceHooks.groovy` are shared. |
| `build/` | Packer templates for the OCI custom images (`build-base-oracle.json`, `build-jvb-oracle.json`, …). |
| `docker/` | The `ops-agent` image Jenkins runs every job inside, plus `ops-git`. |
| `templates/` | Legacy AWS CloudFormation generators (troposphere). Historical; don't extend. |
| `grafana/dashboards/` | Dashboards as JSON. |
| `doc/`, `docs/` | Design notes and plans for individual pieces of work. |

Root-level `*.tfstate` and `*.inventory` files are local leftovers and gitignored. Real state lives
in OCI Object Storage (see below).

## The three repositories

This repo holds code. Two siblings hold the configuration it reads:

- **`infra-configuration`** — Ansible roles and playbooks.
- **`infra-customizations`** — everything deployment-specific: `clouds/`, `config/`, `regions/`,
  `cloud_vpcs/` and one `sites/<environment>/` directory per environment, each with the
  `stack-env.sh` that every script sources. The published repo is a **stub** — a `sites/example/`
  and the surrounding skeleton — meant as the starting point you fill in for your own deployment.
  Jobs take the repo as a parameter (`INFRA_CUSTOMIZATIONS_REPO`, default
  `git@github.com:jitsi/infra-customizations.git`), so a deployment points it at its own copy.

In CI the three are checked out side by side and the customizations are copied *over the top* of the
other two — see `SetupRepos` in `jenkins/groovy/Utils.groovy`:

```sh
cp -a infra-customization/* infra-configuration
cp -a infra-customization/* infra-provisioning
```

Locally you get the same effect with **untracked symlinks at the repo root**, which is why
`scripts/*.sh` can source `clouds/all.sh` and `sites/$ENVIRONMENT/stack-env.sh` directly:

```
ansible  cloud_vpcs  clouds  config  regions  ->  ../infra-customizations/…
sites                                         ->  ../infra-configuration/sites
```

Consequences worth knowing before you spend an hour on a confusing failure:

- They are gitignored and not in git, so **a `git worktree` gets none of them** and anything reading
  them fails oddly — `scripts/oracle_custom_images.py` dies on a missing `config/vars.yml`, and a
  lookup wrapped in `2>/dev/null` just looks like "no image found". Recreate the symlinks in a new
  worktree with **absolute** targets; relative ones resolve against the worktree path.
- `sites` chains onwards: `infra-configuration/sites` is itself a symlink into the customizations
  checkout, since that is where site config actually lives. So editing `sites/<env>/vars.yml` from
  here modifies a *different* repo, and `git status` in this one will never show it. PR site config
  there, code here.
- `ansible/` is not this repo's own content either. Depending on how the checkout is linked, its
  subdirectories (`roles`, `config`, `sites`, `secrets`) resolve into `infra-configuration` or into
  the customizations checkout. Before you edit a file under `ansible/`, run `readlink -f` on it and
  commit the change in the repo it prints. A role edit made from here usually belongs in
  `infra-configuration`.

## How a script expects to be called

Nearly every script follows the same shape:

```bash
ENVIRONMENT=<env> ORACLE_REGION=<region> scripts/deploy-nomad-telegraf.sh
```

- `ENVIRONMENT` and `ORACLE_REGION` are required and the script exits early without them.
- It then sources, in order, whichever of these exist: `sites/$ENVIRONMENT/stack-env.sh` (~230
  scripts), `clouds/all.sh` and `clouds/oracle.sh` (~155 each), and the per-cloud
  `clouds/$ORACLE_REGION-$ENVIRONMENT-oracle.sh` (~73). Everything else — compartment OCIDs, DNS
  zone, tenancy — arrives from those, which is why a script run without them fails in strange
  places rather than up front.
- Resources are named `$ENVIRONMENT-$ORACLE_REGION-$ROLE[-$POOL_TYPE]`, and Nomad datacenters are
  `$ENVIRONMENT-$ORACLE_REGION`.
- `NOMAD_ADDR` defaults to `https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME`, with
  `LOCAL_REGION` falling back to the environment's `OCI_LOCAL_REGION`.
- `scripts/deploy-nomad-<type>.sh` is what the `provision-nomad-job` Jenkins job runs for
  `JOB_TYPE=<type>`. You can run it by hand. The script only computes `NOMAD_ADDR`, so supply the
  Nomad credentials yourself (`NOMAD_TOKEN` or mTLS). Scripts that decrypt `ansible/secrets/*.yml`
  also expect `.vault-password.txt` at the repo root, or `VAULT_PASSWORD_FILE`. Like `sites/`, that
  file comes from the customizations overlay.
- Most deploy scripts pipe a plain jobspec from `nomad/` through `sed` into `nomad job run -`. The
  scripts for the packs in `nomad/jitsi_packs/packs/` (for example JVB, shard backend, autoscaler
  and web release) use `nomad-pack run`, so the `nomad-pack` CLI must be installed as well as
  `nomad`. `deploy-nomad-cloudprober.sh` writes a per-datacenter var-file, runs `nomad-pack render`
  into a temp dir, and then runs `nomad job run` on the rendered `.nomad` file.
- **Re-running a deploy with unchanged vars is a silent no-op.** `nomad job run` compares the new
  spec with the running job. If nothing changed, it creates no allocation and still exits 0, so the
  job does not redeploy. The docker pull policy has no effect on this, and a mutable tag such as
  `latest` does not force a pull. To redeploy, change a var: pin an explicit image tag, such as a
  short commit SHA. `deploy-nomad-opus-transcriber-proxy-monitor.sh` refuses `latest` for this
  reason. `deploy-nomad-autoscaler.sh` still defaults `AUTOSCALER_VERSION` to `latest`.

### Terraform state is per-region, and that bites

The stack wrappers build the backend as
`bucket=tf-state-$ENVIRONMENT`, `endpoint=https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com`.
Object Storage buckets are per-region, so **the same state key holds a different, independent state
in each region**. Passing the wrong `ORACLE_REGION` opens a stale or empty state and Terraform then
tries to *create* resources that already exist. For a stack that is logically global (Vault config,
for instance) pass the environment's own `OCI_LOCAL_REGION`.

## Shard release jobs

`recycle-release-core` replaces every shard of a release with a new one. Its pipeline
(`jenkins/groovy/recycle-release-core/Jenkinsfile`) does this, in order:

1. Lists the existing shards of the release (filtered by `ORACLE_REGION` when set) and keeps the
   list.
2. Runs `expand-release-core`, which starts one `provision-shard` build per new shard (Oracle), one
   new shard for each old one. New shards start in drain, and each `provision-shard` runs
   `validate-shards` on success.
3. Waits at an input step for a human to approve the new shards.
4. Runs `reconfigure-shard-states`: new shards ready, old shards drain.
5. Sleeps `DRAIN_WAIT_PERIOD` seconds (default `21600`, six hours).
6. Runs `destroy-shards` on the list from step 1.

Things that follow from that:

- **The drain wait is a plain `sleep`, and the delete does not re-check shard state.** Setting the
  old shards back to ready during the wait does not save them: the build still deletes them. To
  roll back, abort the build first, then swap the states with `reconfigure-shard-states`.
- **One failed `provision-shard` fails `expand-release-core`**, and the recycle then skips every
  later stage, including finding the new shards. Nothing moves, so the new shards in the regions
  that succeeded sit in drain until someone finishes by hand. Recycle region by region with
  `ORACLE_REGION` when a region is short of capacity, and check first with
  `scripts/check-capacity-oracle.sh shard`.
- **`CLOUDS` does not limit the delete.** The list in step 1 is filtered only by `ORACLE_REGION`,
  but `expand-release-core` builds shards only for `CLOUDS`. Set `CLOUDS` to a subset without
  `ORACLE_REGION`, and the job deletes the old shards in every cloud but replaces them only in the
  subset.
- **Two branch parameters, two different checkouts.** `VIDEO_INFRA_BRANCH` (default `main`) is what
  the job itself checks out (`Utils.SetupRepos`): the scripts and Terraform it runs, from all three
  repos. `RELEASE_BRANCH` is handed to the new instance as `GIT_BRANCH`/`ORACLE_GIT_BRANCH`, and the
  instance configures itself from that ref at boot. If the instance cannot clone that ref,
  `terraform/lib/postinstall-lib.sh` falls back to `main` without failing the boot. A fix to a role
  that runs on the shard has to be on the release ref; a fix to a job has to be on the
  `VIDEO_INFRA_BRANCH` the job runs with. Image builds are separate jobs with their own
  `VIDEO_INFRA_BRANCH`.
- **Shards pick their image by the `Version` tag.** Shard creation takes the newest signal image
  whose `Version` tag equals `SIGNAL_VERSION` (a `latest` or empty component matches any value). A
  `Signal` image build first tags the image from its inputs, then a Packer post-processor
  (`build/build-signal-oracle.json`) runs `scripts/update-image-version-tags.sh`, which rewrites the
  tag from the `installed-versions.json` that `ansible/build-signal.yml` (infra-configuration)
  writes on the image. That playbook gets the jicofo part from `dpkg` with `cut -d'-' -f2`, so a
  jicofo package `1.0-1183-hf-1` tags the image `1183-…` — the same tag as the image without the
  hotfix. The `JicofoHotfix` image type (`build/build-jicofo-hotfix-oracle.json`) takes the tag from
  its `JICOFO_VERSION` input instead.
- **`oracle_custom_images.py --update_version_tags` needs `--jicofo_version`,
  `--jitsi_meet_version` and `--prosody_version`.** They default to empty strings, so without them
  the tag becomes `--` and the version parts of the image name become empty. `--region` defaults to
  `eu-frankfurt-1`, and `--architecture` to `x86_64`.
- **Every `Signal` image build also cleans up old signal images** in each region: it keeps the
  newest `ORACLE_SIGNAL_IMAGE_LIMIT` images without the `production-image` freeform tag and the
  same number with it, and deletes the rest. The tag moves an image to the other group; it does not
  exempt it.

## Conventions

- **Query live state, not state files.** Use the `oci` CLI (`oci compute-management instance-pool
  list`, …) rather than reading `.tfstate`. For node inventory — which hosts run what, which ports —
  ask Consul or Nomad directly (`consul catalog nodes`, `nomad node status`, the Consul HTTP API);
  it's one query instead of per-region OCI loops, and some instances carry tag data that breaks `jq`
  on the raw OCI blob. OCI is still the only source for NSG rules, VNIC layout and instance-pool
  state.
- **Let apt pick versions.** Don't swap an apt install for a pinned tarball from GitHub or
  HashiCorp releases. That is not the same as never pinning: when an upstream release is actively
  broken, pinning the *apt* version is the right response. An unpinned `state=present` install is
  how a bad Consul server release reached several environments at once.
- **Container images come from `ghcr.io/jitsi/*`.** The Docker Hub `jitsi/*:unstable` tags are
  frozen and stale.
- **JVBs are pooled per release, not per shard.** The distinguishing label is `release_number`; a
  pool serves every shard on that release. Comparing bridges by shard produces nonsense.
- **Telegraf targets 1.40.1 on both populations** — the `telegraf:1.40.1` image in
  `nomad/telegraf.hcl`, and `wavefront_collector_version: '1.40.1-1'` installed from apt by the
  `wavefront` role in `infra-configuration`. Keep the two equal: one config dialect, one metric set.
  The fleet is not uniform, though: a VM runs whatever telegraf its base image was built with, long
  after the pin moves. Telegraf *refuses to start* on a config key it does not recognize, so the VM
  template reads the installed binary's version (`roles/wavefront/tasks/telegraf/detect_version.yml`)
  and renders the dialect that version accepts — a newer `infra-configuration` against an older
  image is safe, and playbooks can write either spelling of a field filter. The Nomad job needs no
  such gate: the jobspec pins its own image. To see where the fleet has got to:
  `count by (version) (telegraf_internal_agent_metrics_gathered)`.
- **Telegraf drops behaviour in minor releases, silently.** Between 1.29 and 1.40 it stopped
  collecting protocol stats in `inputs.net` (the `net_tcp_*`/`net_udp_*` series, now `inputs.nstat`
  under `nstat_Tcp*` names), removed `fieldpass`/`fielddrop`, removed `procstat`'s
  `cmdline_tag`/`pid_tag` and `inputs.docker`'s `perdevice`, and narrowed procstat's default field
  set. Some of that fails the config outright; the rest just stops emitting. So never float the
  version, and when you move it, render the config for every population, run it under both versions
  and diff the emitted metric names — reading the changelog is not enough.
- **Deprecated, still present:** `terraform/nomad-server`, `terraform/ops-repo`,
  `terraform/jigasi-proxy` (jigasi proxy runs in Nomad now). Plumb them when a change must be
  exhaustive; don't invest in them otherwise.
- **JJB sees the whole `jobs/` directory.** `scripts/update-jenkins-job-from-yaml.sh` hands JJB
  everything and filters afterwards, so a macro defined in any file is visible to every job.

## Before you open a PR

There is no CI in this repository — nothing runs on push. Whatever you validate, you validate
yourself:

- `git fetch origin` and branch from `origin/main` explicitly. These checkouts are often shared with
  other work in progress, so local `main` can pick up commits between a pull and a branch. After
  opening the PR, check its commit and file lists are only yours.
- Terraform: `terraform init -backend=false && terraform validate` in the stack directory, and
  `terraform fmt`.
- A templated config file (Telegraf, Vector, HAProxy, Prometheus): render it and feed it to the real
  binary, usually in Docker. This catches what reading cannot — for example, Telegraf accepts a
  `namedrop` inside a `[[inputs.prometheus.consul.query]]` block with no error and no warning, and
  silently ignores it, so five dead filters sat unnoticed in `nomad/telegraf.hcl` from 2025 until
  someone measured what was actually being scraped.
- Say in the PR what you ran. "Rendered and parsed with telegraf 1.40.1" is worth more than a
  description of the diff.
