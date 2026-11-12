#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

[ -z "$MAX_WAIT_SECONDS" ] && MAX_WAIT_SECONDS=1200 # 20 min
[ -z "$WAIT_INTERVAL_SECONDS" ] && WAIT_INTERVAL_SECONDS=30

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$POOL_TYPE" ]; then
  echo "No POOL_TYPE found.  Exiting..."
  exit 204
fi

if [  -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## rotate-nomad-instance-pool-oracle: ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## rotate-nomad-instance-pool-oracle: run ansible as $SSH_USER"
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

# the per-type wrapper carries the shape, role and user-data that the pool was provisioned with
CREATE_STACK_SCRIPT="$LOCAL_PATH/../terraform/nomad-instance-pool/create-nomad-${POOL_TYPE}-pool-stack.sh"
if [ ! -e "$CREATE_STACK_SCRIPT" ]; then
  echo "No stack script $CREATE_STACK_SCRIPT for POOL_TYPE $POOL_TYPE. Exiting..."
  exit 2
fi

# The pool name embeds the role, which only the wrapper knows, so match on the tags the stack sets.
function find_instance_pools() {
  oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --lifecycle-state RUNNING --all \
    | jq --arg pt "$POOL_TYPE" --arg prefix "$ENVIRONMENT-$ORACLE_REGION" \
      '[.data[] | select(."freeform-tags".pool_type == $pt
        and ."display-name" == "\($prefix)-\(."defined-tags".jitsi.role)-\($pt)-InstancePool")]'
}

INSTANCE_POOLS=$(find_instance_pools)
INSTANCE_POOL_COUNT=$(echo "$INSTANCE_POOLS" | jq 'length')

if [ "$INSTANCE_POOL_COUNT" != "1" ]; then
  echo "Expected 1 running instance pool with pool_type $POOL_TYPE in $ENVIRONMENT $ORACLE_REGION, found ${INSTANCE_POOL_COUNT:-none}. Exiting..."
  exit 3
fi

INSTANCE_POOL_DETAILS=$(echo "$INSTANCE_POOLS" | jq '.[0]')
INSTANCE_POOL_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.id')
# Exported so the wrapper keeps this size: if its own lookup fails it falls back to 1, and terraform shrinks the pool.
export INSTANCE_POOL_SIZE=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.size')
export ROLE=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '."defined-tags".jitsi.role')
echo -e "\n## rotate-nomad-instance-pool-oracle: rotating $(echo "$INSTANCE_POOL_DETAILS" | jq -r '."display-name"') of size $INSTANCE_POOL_SIZE"

# The stack picks the pool subnet from POOL_PUBLIC, so keep the subnet the pool was provisioned with.
if [ -z "$POOL_PUBLIC" ]; then
  CURRENT_SUBNET_OCID=$(oci compute-management instance-configuration get --region "$ORACLE_REGION" \
    --instance-configuration-id "$(echo "$INSTANCE_POOL_DETAILS" | jq -r '."instance-configuration-id"')" \
    | jq -r '.data."instance-details"."launch-details"."create-vnic-details"."subnet-id"')
  if [ -z "$CURRENT_SUBNET_OCID" ] || [ "$CURRENT_SUBNET_OCID" == "null" ]; then
    echo "Could not read the subnet of the current instance configuration. Set POOL_PUBLIC explicitly. Exiting..."
    exit 4
  fi
  if [ "$CURRENT_SUBNET_OCID" == "$PUBLIC_SUBNET_OCID" ]; then
    export POOL_PUBLIC="true"
  else
    export POOL_PUBLIC="false"
  fi
  export POOL_SUBNET_OCID="$CURRENT_SUBNET_OCID"
fi

OLD_INSTANCE_IDS=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all \
  | jq -r '.data[].id')

# first apply changes to instance configuration, etc
$CREATE_STACK_SCRIPT $SSH_USER

if [ $? -gt 0 ]; then
  echo -e "\n## Nomad instance pool configuration update failed, exiting"
  exit 5
fi

# A missing or wrong-region terraform state makes the apply create a second pool instead of updating this one.
if [ "$(find_instance_pools | jq -r '[.[].id] | join(" ")')" != "$INSTANCE_POOL_ID" ]; then
  echo "## ERROR: after the apply, the running pools with pool_type $POOL_TYPE are not only $INSTANCE_POOL_ID. Check the terraform state. Exiting..."
  exit 6
fi

if [ "$INSTANCE_POOL_SIZE" -eq 0 ]; then
  echo -e "\n## rotate-nomad-instance-pool-oracle: pool size is 0, instance configuration updated, no instances to rotate"
  exit 0
fi

ENVIRONMENT=$ENVIRONMENT INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py inventory

# next scale up by 2X
echo -e "\n## rotate-nomad-instance-pool-oracle: double the size of nomad instance pool"
ENVIRONMENT=$ENVIRONMENT INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py double --wait
if [ $? -gt 0 ]; then
  echo "## ERROR: doubling the instance pool failed. The pool may already be at double size; old instances are untouched. Exiting..."
  exit 225
fi

NEW_INSTANCE_IDS=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all \
  | jq -r --arg old "$OLD_INSTANCE_IDS" '($old | split("\n")) as $o | .data[].id | select(IN($o[]) | not)')
NEW_INSTANCE_COUNT=$(echo "$NEW_INSTANCE_IDS" | grep -c .)
if [ "$NEW_INSTANCE_COUNT" -ne "$INSTANCE_POOL_SIZE" ]; then
  echo "## ERROR: found $NEW_INSTANCE_COUNT new instances, expected $INSTANCE_POOL_SIZE. The pool is left at double size; old instances are untouched. Do not re-run this job. Exiting..."
  exit 226
fi

NEW_IPS=""
for INSTANCE_ID in $NEW_INSTANCE_IDS; do
  NEW_IP=$(oci compute instance list-vnics --region "$ORACLE_REGION" --instance-id "$INSTANCE_ID" | jq -r '.data[] | select(."is-primary") | ."private-ip"')
  if [ -z "$NEW_IP" ]; then
    echo "## ERROR: no private IP found for new instance $INSTANCE_ID. The pool is left at double size; old instances are untouched. Do not re-run this job. Exiting..."
    exit 226
  fi
  NEW_IPS="$NEW_IPS $NEW_IP"
done

# No load balancer fronts these pools, so the new nomad clients themselves are the health gate.
echo -e "\n## rotate-nomad-instance-pool-oracle: waiting for new nomad nodes at ${NEW_IPS} to be ready"
WAIT_TOTAL=0
for IP in $NEW_IPS; do
  while true; do
    NODE_STATE=$(timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP \
      "nomad node status -self -json 2>/dev/null | jq -r '\"\(.Status) \(.SchedulingEligibility) \(.Attributes[\"nomad.version\"])\"'" 2>/dev/null)
    if [[ "$NODE_STATE" == "ready eligible "* ]]; then
      echo "## rotate-nomad-instance-pool-oracle: nomad node on $IP is ready, version ${NODE_STATE##* }"
      break
    fi
    if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
      echo "## ERROR: nomad node on $IP not ready (state: ${NODE_STATE:-query failed}) within $MAX_WAIT_SECONDS seconds in total."
      echo "## The pool is left at double size and the old nodes are untouched. Do not re-run this job. Exiting..."
      exit 227
    fi
    echo "Waiting for nomad node on $IP to be ready (state: ${NODE_STATE:-query failed})"
    sleep $WAIT_INTERVAL_SECONDS
    WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
  done
done

DETACHABLE_IPS=$(ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=$INSTANCE_POOL_SIZE INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py halve --onlyip)
if [ -z "$DETACHABLE_IPS" ]; then
  echo "## ERROR: No IPs found to detach, something went wrong..."
  exit 228
fi

echo -e "\n## rotate-nomad-instance-pool-oracle: draining nomad nodes at ${DETACHABLE_IPS}"
DETACHABLE_NODE_IDS=""
for IP in $DETACHABLE_IPS; do
  NODE_ID=$(timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP \
    "nomad node status -self -json 2>/dev/null | jq -r .ID" 2>/dev/null)
  if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ]; then
    DETACHABLE_NODE_IDS="$DETACHABLE_NODE_IDS $NODE_ID"
    echo -e "\n## rotate-nomad-instance-pool-oracle: captured node ID $NODE_ID for $IP"
  else
    echo -e "\n## rotate-nomad-instance-pool-oracle: WARNING: could not get node ID for $IP"
  fi
  # The wait below cannot tell a drain that never started from an earlier completed one (LastDrain), so stop here.
  if ! timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node drain -self -enable -no-deadline -detach -yes"; then
    echo "## ERROR: could not start nomad drain on $IP. The pool is left at double size."
    echo "## Old nodes at ${DETACHABLE_IPS} still run nomad and consul; some may be draining. Do not re-run this job. Exiting..."
    exit 229
  fi
done

echo -e "\n## rotate-nomad-instance-pool-oracle: waiting for nomad drain to complete before stopping nomad and consul"
WAIT_TOTAL=0
for IP in $DETACHABLE_IPS; do
  while true; do
    DRAIN_STATE=$(timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP \
      "nomad node status -self -json 2>/dev/null | jq -r 'if .DrainStrategy != null then \"draining\" else (.LastDrain.Status // \"never drained\") end'" 2>/dev/null)
    [ "$DRAIN_STATE" == "complete" ] && break
    if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
      # Stopping nomad now would kill the allocations that have not moved yet.
      echo "## ERROR: nomad drain on $IP not complete (state: ${DRAIN_STATE:-query failed}) within $MAX_WAIT_SECONDS seconds in total."
      echo "## The pool is left at double size. Old nodes at ${DETACHABLE_IPS} still run nomad and consul; some may not be drained."
      echo "## Finish the drain, stop nomad and consul, and detach the old instances by hand. Do not re-run this job: it doubles the pool again. Exiting..."
      exit 231
    fi
    echo "Waiting for nomad drain to complete on $IP (state: ${DRAIN_STATE:-query failed})"
    sleep $WAIT_INTERVAL_SECONDS
    WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
  done
done

for IP in $DETACHABLE_IPS; do
  echo -e "\n## rotate-nomad-instance-pool-oracle: stopping nomad and consul on $IP"
  timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "sudo service nomad stop && sudo service consul stop"
done

# purge the stopped old nodes from Nomad cluster state so system jobs don't show unplaced
if [ -n "$DETACHABLE_NODE_IDS" ]; then
  [ -z "$NOMAD_ADDR" ] && export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
  for NODE_ID in $DETACHABLE_NODE_IDS; do
    echo -e "\n## rotate-nomad-instance-pool-oracle: purging nomad node $NODE_ID"
    PURGE_RESPONSE=$(curl -sf -X POST "$NOMAD_ADDR/v1/node/$NODE_ID/purge")
    if [ $? -eq 0 ] && echo "$PURGE_RESPONSE" | jq -e 'has("NodeModifyIndex")' > /dev/null 2>&1; then
      echo "$PURGE_RESPONSE" | jq -r '"purged, eval \(.EvalIDs[0] // "none")"'
    else
      echo "## WARNING: purge request to $NOMAD_ADDR failed for node $NODE_ID"
    fi
  done
fi

# scale down the old instances
echo -e "\n## rotate-nomad-instance-pool-oracle: halve the size of nomad instance pool"
ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=$INSTANCE_POOL_SIZE INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py halve --wait

# pool.py halve reports a failed detach but still exits 0, so check the result instead.
FINAL_POOL_SIZE=$(oci compute-management instance-pool get --region "$ORACLE_REGION" --instance-pool-id "$INSTANCE_POOL_ID" | jq -r '.data.size')
FINAL_INSTANCE_IDS=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all \
  | jq -r '.data[].id' | sort)
if [ "$FINAL_POOL_SIZE" != "$INSTANCE_POOL_SIZE" ] || [ "$FINAL_INSTANCE_IDS" != "$(echo "$NEW_INSTANCE_IDS" | sort)" ]; then
  echo "## ERROR: pool size is ${FINAL_POOL_SIZE:-unknown}, expected $INSTANCE_POOL_SIZE."
  echo "## Instances in the pool: ${FINAL_INSTANCE_IDS:-none found}. Expected only the new instances: ${NEW_INSTANCE_IDS}"
  exit 230
fi
echo -e "\n## rotate-nomad-instance-pool-oracle: pool is back to size $INSTANCE_POOL_SIZE with only the new instances"
