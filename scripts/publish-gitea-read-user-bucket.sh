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

if ! vault token lookup >/dev/null 2>&1; then
  echo "Not logged in to vault at ${VAULT_ADDR:-<unset>}; run scripts/vault-login.sh from infra-customizations-private first"
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

exit $FINAL_RET
