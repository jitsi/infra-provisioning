#!/bin/bash

# Tells the per-region Gitea mirrors to pull from GitHub now, instead of waiting
# for their next scheduled interval. See JIT-16092.
#
# Why a Consul key rather than calling the mirrors directly: each region runs two
# Gitea replicas behind one Fabio route, each with its own database, so an API
# call to the mirror hostname only ever syncs whichever replica it lands on. Every
# replica templates this key and nomad signals its sync-gate when the value
# changes, so one write per region reaches both replicas, and a replica that
# starts later just reads the current value.
#
# Run this after a release tags a repo. Boots check out a specific tag, so
# without it a boot can reach a replica that has not pulled the tag yet. That
# still works (the boot path falls back to github) but it defeats the point of
# having a local mirror.
#
# Usage: ENVIRONMENT=prod-8x8 scripts/trigger-nomad-gitea-mirror-sync.sh <label>
#   <label>      what is being released, recorded as the key's value for the
#                logs. Defaults to $GIT_BRANCH, or "manual".
#   REGIONS      defaults to the environment's NOMAD_REGIONS.
#   CONSUL_HOST  overrides the consul endpoint for every region, for a one-off.

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

TRIGGER_LABEL="$1"
[ -z "$TRIGGER_LABEL" ] && TRIGGER_LABEL="$GIT_BRANCH"
[ -z "$TRIGGER_LABEL" ] && TRIGGER_LABEL="manual"

[ -z "$REGIONS" ] && REGIONS="$NOMAD_REGIONS"
if [ -z "$REGIONS" ]; then
  echo "No REGIONS or NOMAD_REGIONS set, exiting"
  exit 1
fi

# A timestamp is appended so a repeat of the same tag still changes the rendered
# value: nomad only signals when the template output actually differs.
TRIGGER_VALUE="$TRIGGER_LABEL $(date -u +%Y-%m-%dT%H:%M:%SZ)"

FINAL_RET=0
for REGION in $REGIONS; do
  # Each region's consul is reached directly. dc is still named explicitly so the
  # write cannot land in a neighbouring datacenter if a hostname is ever repointed.
  REGION_CONSUL_HOST="$CONSUL_HOST"
  [ -z "$REGION_CONSUL_HOST" ] && REGION_CONSUL_HOST="$ENVIRONMENT-$REGION-consul.$TOP_LEVEL_DNS_ZONE_NAME"
  KV_URL="https://$REGION_CONSUL_HOST/v1/kv/gitea-mirror/sync-trigger?dc=$ENVIRONMENT-$REGION"

  RESPONSE=$(curl -s -m 20 -d "$TRIGGER_VALUE" -X PUT "$KV_URL")
  if [ $? -eq 0 ] && [ "$RESPONSE" == "true" ]; then
    echo "triggered a mirror sync in $ENVIRONMENT-$REGION for '$TRIGGER_VALUE'"
  else
    # Never fatal to a release: the mirrors still pull on their own interval, and
    # boots fall back to github for anything not mirrored yet.
    echo "WARNING: could not trigger a mirror sync in $ENVIRONMENT-$REGION: $RESPONSE"
    FINAL_RET=1
  fi
done

exit $FINAL_RET
