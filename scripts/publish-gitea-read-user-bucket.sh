#!/bin/bash

# Publishes the read-only Gitea mirror user from Vault into an environment's
# boot bucket (jvb-bucket-<env>, one per region), as the object gitea-read-user
# (JSON: username, password). Booting VMs read it with their instance principal
# in fetch_credentials (terraform/lib/postinstall-lib.sh), exactly like the
# ansible-vault password and deploy key already there, and write it to a netrc
# for the mirror host. See JIT-16092.
#
# This is the transition path: the plan's end state has boots read the secret
# straight from Vault via OCI instance auth, which is not built yet. The bucket
# is per environment while the secret is per Vault, so run this once per
# environment, after scripts/seed-gitea-read-user.sh against that
# environment's Vault, and again after any rotation.
#
# Usage: ENVIRONMENT=stage-8x8 scripts/publish-gitea-read-user-bucket.sh
#   REGIONS      defaults to the environment's NOMAD_REGIONS (where mirrors run)
#   SECRET_PATH  default secret/default/gitea/read-user
#   OBJECT_NAME  default gitea-read-user
#   DELETE=true  remove the object instead (boots then fall back to github for
#                the private repo; the public repos still come from the mirror)

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

# Which vault the credential is read FROM. Derived from VAULT_ENVIRONMENT the
# same way the vault-* terraform wrappers do, rather than inherited from an
# ambient VAULT_ADDR: ENVIRONMENT selects the destination bucket, so letting the
# shell's VAULT_ADDR select the source secret makes it easy to publish one
# vault's credential into another environment's bucket. That is exactly what
# happened to ops-dev on 2026-09-09 -- its bucket ended up holding a password no
# mirror had, so every boot silently fell back to github.
#
# ops-dev (and anything else whose nomad talks to a non-default vault) needs
# VAULT_ENVIRONMENT set explicitly. Being logged in to a different vault now
# fails outright instead of publishing the wrong credential.
[ -z "$VAULT_ENVIRONMENT" ] && VAULT_ENVIRONMENT="ops-prod"
if [ -z "$VAULT_ADDR" ] || [ "$VAULT_ADDR_DERIVE" != "false" ]; then
  if [ -n "$VAULT_REGION" ]; then
    export VAULT_ADDR="https://${VAULT_ENVIRONMENT}-${VAULT_REGION}-vault.jitsi.net"
  else
    export VAULT_ADDR="https://${VAULT_ENVIRONMENT}-vault.jitsi.net"
  fi
fi

[ -z "$SECRET_PATH" ] && SECRET_PATH="secret/default/gitea/read-user"
[ -z "$OBJECT_NAME" ] && OBJECT_NAME="gitea-read-user"
[ -z "$BUCKET_NAME" ] && BUCKET_NAME="jvb-bucket-${ENVIRONMENT}"
[ -z "$REGIONS" ] && REGIONS="$NOMAD_REGIONS"
if [ -z "$REGIONS" ]; then
  echo "No REGIONS or NOMAD_REGIONS set, exiting"
  exit 1
fi

FINAL_RET=0
if [ "$DELETE" == "true" ]; then
  for REGION in $REGIONS; do
    if oci os object delete --force --region "$REGION" --bucket-name "$BUCKET_NAME" --name "$OBJECT_NAME"; then
      echo "deleted $OBJECT_NAME from $BUCKET_NAME in $REGION"
    else
      echo "WARNING: could not delete $OBJECT_NAME from $BUCKET_NAME in $REGION"
      FINAL_RET=1
    fi
  done
  exit $FINAL_RET
fi

echo "reading $SECRET_PATH from $VAULT_ADDR -> jvb-bucket-${ENVIRONMENT} ($REGIONS)"
if ! vault token lookup >/dev/null 2>&1; then
  echo "Not logged in to vault at ${VAULT_ADDR:-<unset>}; run scripts/vault-login.sh from infra-customizations-private first"
  echo "(VAULT_ENVIRONMENT=$VAULT_ENVIRONMENT selected that vault; set it to the vault this environment's nomad uses)"
  exit 203
fi

# Written to a private temp file, never passed on a command line.
CREDS_FILE=$(mktemp)
trap 'rm -f "$CREDS_FILE"' EXIT
chmod 600 "$CREDS_FILE"
if ! vault kv get -format=json "$SECRET_PATH" | jq -e '.data.data | {username, password} | select(.username != null and .password != null)' > "$CREDS_FILE"; then
  echo "Could not read username and password from $SECRET_PATH in $VAULT_ADDR; run scripts/seed-gitea-read-user.sh first"
  exit 1
fi

for REGION in $REGIONS; do
  if oci os object put --force --region "$REGION" --bucket-name "$BUCKET_NAME" --name "$OBJECT_NAME" --file "$CREDS_FILE" >/dev/null; then
    echo "published $OBJECT_NAME to $BUCKET_NAME in $REGION"
  else
    echo "WARNING: could not publish $OBJECT_NAME to $BUCKET_NAME in $REGION"
    FINAL_RET=1
  fi
done

# Publishing succeeds regardless of whether the credential matches the user the
# mirrors actually created, and a mismatch is silent -- boots just fall back to
# github. Always confirm.
[ $FINAL_RET -eq 0 ] && echo "now confirm it works: ENVIRONMENT=$ENVIRONMENT ORACLE_REGION=<region> scripts/verify-nomad-gitea-mirror.sh"

exit $FINAL_RET
