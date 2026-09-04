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
# Usage: ENVIRONMENT=prod-8x8 scripts/trigger-nomad-gitea-mirror-sync.sh <label> [ssh-user]
#   <label>   what is being released, recorded as the key's value for the logs.
#             Defaults to $GIT_BRANCH, or "manual".
#   REGIONS   defaults to the environment's NOMAD_REGIONS.

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

if [ -z "$2" ]; then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$2
fi

[ -z "$REGIONS" ] && REGIONS="$NOMAD_REGIONS"
if [ -z "$REGIONS" ]; then
  echo "No REGIONS or NOMAD_REGIONS set, exiting"
  exit 1
fi

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"

# A timestamp is appended so a repeat of the same tag still changes the rendered
# value: nomad only signals when the template output actually differs.
TRIGGER_VALUE="$TRIGGER_LABEL $(date -u +%Y-%m-%dT%H:%M:%SZ)"

PORT_OCI=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

# Consul forwards KV writes to another datacenter via ?dc=, so one tunnel to the
# environment's local region covers every region in it.
ssh -fNT -L127.0.0.1:$PORT_OCI:$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.$DEFAULT_DNS_ZONE_NAME
if [ $? -ne 0 ]; then
  echo "Failed to open the consul tunnel, exiting"
  exit 2
fi

OCI_CONSUL_HOST="consul-local.$TOP_LEVEL_DNS_ZONE_NAME"
OCI_CONSUL_URL="https://$OCI_CONSUL_HOST:$PORT_OCI"

FINAL_RET=0
for REGION in $REGIONS; do
  KV_URL="$OCI_CONSUL_URL/v1/kv/gitea-mirror/sync-trigger?dc=$ENVIRONMENT-$REGION"
  RESPONSE=$(curl -s --resolve $OCI_CONSUL_HOST:$PORT_OCI:127.0.0.1 -d "$TRIGGER_VALUE" -X PUT "$KV_URL")
  if [ $? -eq 0 ] && [ "$RESPONSE" == "true" ]; then
    echo "triggered a mirror sync in $ENVIRONMENT-$REGION for '$TRIGGER_VALUE'"
  else
    # Never fatal to a release: the mirrors still pull on their own interval, and
    # boots fall back to github for anything not mirrored yet.
    echo "WARNING: could not trigger a mirror sync in $ENVIRONMENT-$REGION: $RESPONSE"
    FINAL_RET=1
  fi
done

SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | grep -v grep | awk '{print $2}')
[ -n "$SSH_OCI_PID" ] && kill $SSH_OCI_PID

exit $FINAL_RET
