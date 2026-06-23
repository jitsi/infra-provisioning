# ops-repo test environment (Debian Trixie dual-signing)

Runbook for standing up a throwaway ops-repo in **ops-dev** backed by a separate
`ops-repo-test` bucket, to validate the Debian Trixie / APT 3.0 dual-signing flow
end-to-end **without touching the production `ops-repo` bucket**. See JIT-15930.

The production repo is unaffected throughout: every step targets a distinct
bucket (`ops-repo-test`), Nomad job (`ops-repo-test`), hostname, and Vault path.

## What got parameterized

| Knob | Where | Default (prod) | Test value |
|------|-------|----------------|------------|
| `OPS_REPO_BUCKET` | `reconfigure-ops-repo` param / `update-ops-repo.sh` / `deploy-nomad-ops-repo.sh` | `ops-repo` | `ops-repo-test` |
| `NEW_KEYID` | `reconfigure-ops-repo` param → `sign-release.sh` | empty (legacy single-sign) | modern key fingerprint |
| `OPS_REPO_*_CREDENTIAL_ID` | `reconfigure-ops-repo` params | `ops-repo-{secring,pubring,secring-passphrase}` | combined-key test credentials |
| `JOB_NAME` | `deploy-nomad-ops-repo.sh` (→ `nomad/ops-repo.hcl`) | `ops-repo` | `ops-repo-test` |
| `OPS_REPO_HOSTNAME` | `deploy-nomad-ops-repo.sh` | from `ansible/secrets/ops-repo.yml` | test hostname |

`clouds/oracle.sh` still sets `OPS_REPO_BUCKET=ops-repo`; the scripts capture a
caller-provided value *before* sourcing it and re-apply it afterwards, so prod
behavior is unchanged when nothing is overridden.

## 1. Create the test bucket (terraform)

```bash
cd terraform/ops-repo-bucket
ENVIRONMENT=ops-dev ORACLE_REGION=us-phoenix-1 OPS_REPO_BUCKET_NAME=ops-repo-test ./ops-repo-bucket.sh
```

Creates `ops-repo-test` in namespace `fr4eeztjonbe`, state at
`tf-state-ops-dev/ops-repo-bucket/ops-repo-test/terraform.tfstate`.

## 2. Seed the bucket layout

The repo serves `root /mnt/ops-repo/repo`, and `update-ops-repo.sh` builds under
`repo/debian` with mini-dinstall, reading `jitsi-debian-pkg.conf` from the mount
root. Seed the same structure into `ops-repo-test`:

```
jitsi-debian-pkg.conf                       # mini-dinstall config (copy from prod bucket)
repo/debian/mini-dinstall/incoming/         # incoming dir mini-dinstall reads (.deb + .changes + .buildinfo)
repo/debian/unstable/archive.key            # combined public key (added in step 4/5)
```

> All `oci os` commands below need `--region us-phoenix-1` (the bucket region).

```bash
# copy the prod mini-dinstall config as a starting point
oci os object get -bn ops-repo --name jitsi-debian-pkg.conf --file /tmp/jitsi-debian-pkg.conf --region us-phoenix-1
# ensure release_signscript in it points at the checked-out scripts/sign-release.sh
oci os object put  -bn ops-repo-test --name jitsi-debian-pkg.conf --file /tmp/jitsi-debian-pkg.conf --region us-phoenix-1
```

mini-dinstall installs from `.changes` uploads (not bare `.debs`), so each sample
needs its `.deb` + `.changes` + `.buildinfo`. A couple of throwaway
`jitsi-ops-repo-test` packages (v1.0.0 and v1.0.1, `Architecture: all`,
`Distribution: unstable`) have already been seeded into
`repo/debian/mini-dinstall/incoming/`. To regenerate them:

```bash
# build a native arch:all package (deb + changes + buildinfo) in a container, then upload
docker run --rm -v "$PWD/out:/build" debian:bookworm bash -c '
  apt-get update -qq && apt-get install -y -qq build-essential debhelper dpkg-dev
  cd /build && rm -rf src && mkdir -p src/debian/source && cd src
  printf "3.0 (native)\n" > debian/source/format
  printf "#!/usr/bin/make -f\n%%:\n\tdh \$@\n" > debian/rules && chmod +x debian/rules
  cat > debian/control <<CTL
Source: jitsi-ops-repo-test
Maintainer: Jitsi Ops <ops@jitsi.net>
Build-Depends: debhelper-compat (= 13)
Standards-Version: 4.6.2

Package: jitsi-ops-repo-test
Architecture: all
Depends: \${misc:Depends}
Description: Sample package for ops-repo-test validation
 Throwaway package; safe to remove.
CTL
  cat > debian/changelog <<CHG
jitsi-ops-repo-test (1.0.0) unstable; urgency=medium

  * Sample package for ops-repo-test validation.

 -- Jitsi Ops <ops@jitsi.net>  Mon, 23 Jun 2026 12:00:00 +0000
CHG
  dpkg-buildpackage -b -us -uc'
for f in out/jitsi-ops-repo-test_*; do
  oci os object put -bn ops-repo-test --name "repo/debian/mini-dinstall/incoming/$(basename "$f")" --file "$f" --region us-phoenix-1 --force
done
```

## 3. Produce the dual-key signing material

Use the rotation job (JIT-15930, infra-customizations-private) pointed at the
**ops-dev** Vault:

```
rotate-ops-repo-signing-key  DRY_RUN=true            # review new_keyid
rotate-ops-repo-signing-key  DRY_RUN=false VAULT_ENVIRONMENT=ops-dev
```

Note the `new_keyid` from the output — that is the `NEW_KEYID` for step 4.

Until the signing jobs read from Vault (JIT-15934), create **test** Jenkins file
credentials from the combined material the rotation produced, so the reconfigure
job can sign with both keys:

- `ops-repo-secring-test`           ← combined `secring` (base64-decoded)
- `ops-repo-pubring-test`           ← combined `pubring` (base64-decoded)
- `ops-repo-secring-passphrase-test`← the (unchanged) passphrase

## 4. Reconfigure (build + dual-sign) the test bucket

Run the `reconfigure-ops-repo` job with:

- `VIDEO_INFRA_BRANCH` = the JIT-15930 dual-sign branch (so `sign-release.sh`
  emits the dual-signed `InRelease`)
- `OPS_REPO_BUCKET` = `ops-repo-test`
- `NEW_KEYID` = the fingerprint from step 3
- `OPS_REPO_SECRING_CREDENTIAL_ID` = `ops-repo-secring-test`
- `OPS_REPO_PUBRING_CREDENTIAL_ID` = `ops-repo-pubring-test`
- `OPS_REPO_SECRING_PASSPHRASE_CREDENTIAL_ID` = `ops-repo-secring-passphrase-test`

Then publish the combined public key to the bucket:

```bash
oci os object put -bn ops-repo-test --name repo/debian/unstable/archive.key --file archive.key --region us-phoenix-1
```

## 5. Deploy the serving job in ops-dev

```bash
ENVIRONMENT=ops-dev ORACLE_REGION=us-phoenix-1 \
  OPS_REPO_BUCKET=ops-repo-test \
  JOB_NAME=ops-repo-test \
  OPS_REPO_HOSTNAME=ops-repo-test.<ops-dev-zone> \
  scripts/deploy-nomad-ops-repo.sh
```

Prerequisites in ops-dev: the `secret/default/ops-repo/s3` Vault secret (s3fs
object-storage key), and a DNS/fabio route for `OPS_REPO_HOSTNAME` (the job
advertises `int-urlprefix-<hostname>/`). The htpasswd user/pass come from
`ansible/secrets/ops-repo.yml`.

## 6. Verify on Debian Trixie

```bash
docker run --rm -it debian:trixie bash
# install ca-certificates; drop the combined archive.key (dearmored) into
# /etc/apt/keyrings/jitsi-archive-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/jitsi-archive-keyring.gpg] \
  https://<user>:<pass>@ops-repo-test.<ops-dev-zone>/debian unstable/' \
  > /etc/apt/sources.list.d/jitsi.list
apt-get update     # expect exit 0, no "not signed"
apt-get install -y <a-test-package>
```

Also confirm an existing distro (e.g. Bookworm) still verifies via the legacy key.

## 7. Teardown

```bash
nomad job stop -purge ops-repo-test                     # in ops-dev
cd terraform/ops-repo-bucket
ACTION=destroy ENVIRONMENT=ops-dev OPS_REPO_BUCKET_NAME=ops-repo-test ./ops-repo-bucket.sh
# remove the test Jenkins credentials and the ops-dev Vault signing secret if desired
```
