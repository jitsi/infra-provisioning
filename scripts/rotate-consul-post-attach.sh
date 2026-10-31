#!/bin/bash
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# find the instance from the load balancer (should only be one for consul)
# grab the ip from the load-balancer-backends field
INSTANCE_PRIMARY_PRIVATE_IP="$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" \
  --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all | \
  jq -r '.data[0]."load-balancer-backends"[0]."backend-name"|split(":")[0]')"

if [ -f "./nomad-keyring.tar.gz" ]; then
  echo "## rotate-consul-post-attach: copying nomad keyring material to $INSTANCE_PRIMARY_PRIVATE_IP" 
  scp -F $LOCAL_PATH/../config/ssh.config ./nomad-keyring.tar.gz $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP:/tmp/nomad-keyring.tar.gz
  echo "## rotate-consul-post-attach: extracting nomad keyring material on $INSTANCE_PRIMARY_PRIVATE_IP"
  timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "sudo tar -xzf /tmp/nomad-keyring.tar.gz -C / && sudo rm -f /tmp/nomad-keyring.tar.gz"
  timeout 120 ssh -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "sudo service nomad restart"
  rm ./nomad-keyring.tar.gz
else 
  echo "## rotate-consul-post-attach: no nomad keyring material to copy, skipping copy and extraction"
fi

echo "## rotate-consul-post-attach re-running terraform"
$LOCAL_PATH/../terraform/consul-server/create-consul-server-oracle.sh $SSH_USER

# remove the replaced node from nomad state; otherwise it sits as "down" until the 24h node
# GC and the system jobs count it as an unplaced node ("9/11 degraded" in the UI)
if [ -n "$DETACHED_NOMAD_NODE_ID" ]; then
  # any region's nomad LB reaches the global raft; prefer the one the rotation is in
  [ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
  [ -z "$LOCAL_REGION" ] && LOCAL_REGION="$ORACLE_REGION"
  [ -z "$NOMAD_ADDR" ] && export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
  echo "## rotate-consul-post-attach: purging nomad node $DETACHED_NOMAD_NODE_ID"
  # check curl's own status: piped straight into jq, a failed request exits 0 and prints nothing
  PURGE_RESPONSE=$(curl -sf -X POST "$NOMAD_ADDR/v1/node/$DETACHED_NOMAD_NODE_ID/purge")
  if [ $? -eq 0 ] && echo "$PURGE_RESPONSE" | jq -e 'has("NodeModifyIndex")' > /dev/null 2>&1; then
    echo "$PURGE_RESPONSE" | jq -r '"## rotate-consul-post-attach: purged, eval \(.EvalIDs[0] // "none")"'
  else
    echo "## rotate-consul-post-attach: WARNING: purge request to $NOMAD_ADDR failed for node $DETACHED_NOMAD_NODE_ID"
  fi
  unset DETACHED_NOMAD_NODE_ID
fi
