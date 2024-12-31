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
  rm ./nomad-keyring.tar.gz
else 
  echo "## rotate-consul-post-attach: no nomad keyring material to copy, skipping copy and extraction"
fi

echo "## rotate-consul-post-attach re-running terraform"
$LOCAL_PATH/../terraform/consul-server/create-consul-server-oracle.sh $SSH_USER
