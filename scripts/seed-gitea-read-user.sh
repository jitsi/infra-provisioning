#!/bin/bash

# Seeds the read-only Gitea user that booting VMs use to clone the private repo
# from the per-region Gitea mirror (JIT-16092). Writes username + password to
# Vault at secret/default/gitea/read-user; every mirror replica's init task
# creates the same user from it, so the credential works whichever replica a
# boot lands on. See doc/git-mirror-bootstrap-plan.md, decision 6 (revised).
#
# Run once per Vault (ops-dev, ops-prod), not per environment. Afterwards the
# mirrors have to be redeployed to pick the user up, and the credential has to
# be published to each environment's boot bucket with
# scripts/publish-gitea-read-user-bucket.sh.
#
# Usage: (vault login first, e.g. VAULT_ENVIRONMENT=ops-dev \
#           ../infra-customizations-private/scripts/vault-login.sh)
#   scripts/seed-gitea-read-user.sh
#     GITEA_READ_USER   username, default mirror-reader
#     ROTATE=true       overwrite an existing secret with a new password. The
#                       mirrors converge on their next deploy or restart; until
#                       every one has, boots on the old password fall back to
#                       github for the private repo.
#     SECRET_PATH       default secret/default/gitea/read-user

set -e

[ -z "$GITEA_READ_USER" ] && GITEA_READ_USER="mirror-reader"
[ -z "$SECRET_PATH" ] && SECRET_PATH="secret/default/gitea/read-user"

if ! vault token lookup >/dev/null 2>&1; then
  echo "Not logged in to vault at ${VAULT_ADDR:-<unset>}; run scripts/vault-login.sh from infra-customizations-private first"
  exit 203
fi

if vault kv get "$SECRET_PATH" >/dev/null 2>&1; then
  if [ "$ROTATE" != "true" ]; then
    echo "$SECRET_PATH already exists in $VAULT_ADDR; set ROTATE=true to replace the password"
    echo "username: $(vault kv get -field=username "$SECRET_PATH")"
    exit 0
  fi
  echo "Rotating the password in $SECRET_PATH"
fi

# Alphanumeric only, on purpose: the password ends up in a netrc line and may
# end up in a URL, and neither has a portable way to quote anything else.
# 40 alphanumeric characters is ~238 bits, far more than the hash needs.
PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)
if [ "${#PASSWORD}" -ne 40 ]; then
  echo "Failed to generate a password"
  exit 1
fi

vault kv put "$SECRET_PATH" username="$GITEA_READ_USER" password="$PASSWORD" >/dev/null
echo "Wrote $SECRET_PATH (username $GITEA_READ_USER) to $VAULT_ADDR"
echo "Next: redeploy the gitea mirrors that use this vault, then publish to the boot buckets with scripts/publish-gitea-read-user-bucket.sh"
