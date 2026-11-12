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

# if no load balancer is available to detect bootup health then
# wait a fixed period between instances when rotating
[ -z "$STARTUP_GRACE_PERIOD_SECONDS" ] && STARTUP_GRACE_PERIOD_SECONDS=300 # 5 min

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [  -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## rotate-nomad-oracle: ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## rotate-nomad-oracle: run ansible as $SSH_USER"
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

[ -z "$ROLE" ] && ROLE="nomad-pool"
[ -z "$POOL_TYPE" ] && POOL_TYPE="general"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$POOL_TYPE"

[ -z "$NAME_ROOT" ] && NAME_ROOT="$NAME"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${NAME_ROOT}-InstancePool"

INSTANCE_POOL_DETAILS=$(oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --lifecycle-state RUNNING --all --display-name "$INSTANCE_POOL_NAME" | jq .data[0])

if [ -z "$INSTANCE_POOL_DETAILS" ] || [ "$INSTANCE_POOL_DETAILS" == "null" ]; then
  echo "No instance pool found with name $INSTANCE_POOL_NAME. Exiting..."
  exit 3
else
  INSTANCE_POOL_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.id')
  export INSTANCE_POOL_SIZE=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.size')

  EXISTING_INSTANCE_DATA=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all)
  EXISTING_INSTANCES="$(echo "$EXISTING_INSTANCE_DATA" | jq .data)"
  INSTANCE_COUNT=$(echo $EXISTING_INSTANCES| jq -r ".|length")

  if [[ $INSTANCE_COUNT -gt 0 ]]; then
    # more than local region found, check/perform association
    for i in `seq 0 $((INSTANCE_COUNT-1))`; do
      DETAILS="$(echo "$EXISTING_INSTANCES" | jq ".[$i]")"
      INSTANCE_ID="$(echo "$DETAILS"  | jq -r ".id")"

      # look up current load balancer, use if defined
      LOAD_BALANCER_ID=$(echo "$DETAILS"  | jq -r '."load-balancer-backends"|first|."load-balancer-id"')
      [[ "$LOAD_BALANCER_ID" == "null" ]] && LOAD_BALANCER_ID=
      LB_BACKEND_SET_NAME=$(echo "$DETAILS"  | jq -r '."load-balancer-backends"|first|."backend-set-name"')
      [[ "$LB_BACKEND_SET_NAME" == "null" ]] && LB_BACKEND_SET_NAME=
    done
  fi

  # first apply changes to instance configuration, etc
  $LOCAL_PATH/../terraform/nomad-pool/create-nomad-pool-stack.sh $SSH_USER

  if [ $? -gt 0 ]; then
    echo -e "\n## Nomad pool configuration update failed, exiting"
    exit 5
  fi


  ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py inventory

  # check if the load balancer is healthy before proceeding
  if [ ! -z "$LOAD_BALANCER_ID" ]; then
    CURRENT_LB_BACKEND_HEALTH=$(oci lb backend-set-health get --region "$ORACLE_REGION" --backend-set-name "$LB_BACKEND_SET_NAME" --load-balancer-id "$LOAD_BALANCER_ID")
    CURRENT_LB_BACKEND_OVERALL_STATUS=$(echo $CURRENT_LB_BACKEND_HEALTH | jq -r '.data.status')
    if [ "$CURRENT_LB_BACKEND_OVERALL_STATUS" != 'OK' ]; then
      echo "State of existing load balancer for nomad instance pool is not ok; exiting before scale up."
      exit 5
    fi
  fi

  # next scale up by 2X
  echo -e "\n## rotate-nomad-poool-oracle: double the size of nomad pool"
  ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py double --wait

  # wait for load balancer to see new instances go healthy
  if [ ! -z "$LOAD_BALANCER_ID" ]; then
    # Wait for the LB to see all the backends (including the newly added instance) healthy to avoid downtime
    WAIT_TOTAL=0
    LATEST_LB_BACKEND_HEALTH=$(oci lb backend-set-health get --region "$ORACLE_REGION" --backend-set-name "$LB_BACKEND_SET_NAME" --load-balancer-id "$LOAD_BALANCER_ID")
    LATEST_LB_BACKEND_OVERALL_STATUS=$(echo $LATEST_LB_BACKEND_HEALTH | jq -r '.data.status')
    while [ "$LATEST_LB_BACKEND_OVERALL_STATUS" != 'OK' ]; do
      if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
        echo "Exceeding max waiting time of $MAX_WAIT_SECONDS seconds for the load balancer backend state to reach OK status again, current status is $LATEST_LB_BACKEND_OVERALL_STATUS. Something is wrong, exiting..."
        exit 224
      fi

      echo "Waiting for the load balancer backend state to reach OK status again. Current status is $LATEST_LB_BACKEND_OVERALL_STATUS."
      sleep $WAIT_INTERVAL_SECONDS
      WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
      LATEST_LB_BACKEND_HEALTH=$(oci lb backend-set-health get --region "$ORACLE_REGION" --backend-set-name "$LB_BACKEND_SET_NAME" --load-balancer-id "$LOAD_BALANCER_ID")
      LATEST_LB_BACKEND_OVERALL_STATUS=$(echo $LATEST_LB_BACKEND_HEALTH | jq -r '.data.status')
    done
    # confirm that final count matches expectations
    BACKEND_COUNT=$(echo $LATEST_LB_BACKEND_HEALTH | jq -r '.data."total-backend-count"')
    EXPECTED_COUNT=$(( $INSTANCE_COUNT * 2))
    if [[ "$BACKEND_COUNT" -ne "$EXPECTED_COUNT" ]]; then
      echo "Found $BACKEND_COUNT healthy backends, expected $EXPECTED_COUNT. Something went wrong, exiting..."
      exit 225
    fi
  else
    # No load balancer to detect healthy state, so wait for fixed duration before continuing
    if [[ $i -lt $((INSTANCE_COUNT-1)) ]]; then
      echo "Waiting for $STARTUP_GRACE_PERIOD_SECONDS seconds before rotating next instance"
      sleep $STARTUP_GRACE_PERIOD_SECONDS
    fi
  fi

  DETACHABLE_IPS=$(ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py halve --onlyip)
  if [ -z "$DETACHABLE_IPS" ]; then
    echo "## ERROR: No IPs found to detach, something went wrong..."
    exit 226
  fi

  # The LB health check is fabio's /health, which stays OK after consul stops. Without this the LBs
  # keep sending requests to a fabio whose route table stopped updating, so a service that moves gets no route.
  echo -e "\n## rotate-nomad-poool-oracle: draining load balancer backends for ${DETACHABLE_IPS}"
  LB_DRAIN_BACKENDS=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all \
    | jq -r --arg ips "$DETACHABLE_IPS" '[$ips | splits(" +") | select(. != "")] as $detach
        | .data[]."load-balancer-backends"[]?
        | select(."backend-name" | split(":")[0] | IN($detach[]))
        | [."load-balancer-id", ."backend-set-name", ."backend-name"] | @tsv')
  if [ -n "$LOAD_BALANCER_ID" ]; then
    for IP in $DETACHABLE_IPS; do
      grep -q $'\t'"$IP:" <<< "$LB_DRAIN_BACKENDS" || echo "## WARNING: no load balancer backends found for $IP, it keeps receiving requests"
    done
  fi
  # The health gate above checks only the first of the pool's LBs. Wait for every backend set, so that
  # draining the old backends never leaves one with no healthy backend.
  for BACKEND_SET in $(cut -f1,2 <<< "$LB_DRAIN_BACKENDS" | sort -u | tr '\t' ','); do
    WAIT_TOTAL=0
    until [ "$(oci lb backend-set-health get --region "$ORACLE_REGION" --load-balancer-id "${BACKEND_SET%,*}" --backend-set-name "${BACKEND_SET#*,}" | jq -r '.data.status')" == "OK" ]; do
      if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
        echo "## WARNING: backend set ${BACKEND_SET#*,} not OK after $MAX_WAIT_SECONDS seconds, draining anyway"
        break
      fi
      echo "Waiting for backend set ${BACKEND_SET#*,} to reach OK status"
      sleep $WAIT_INTERVAL_SECONDS
      WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
    done
  done
  while IFS=$'\t' read -r BACKEND_LB_ID BACKEND_SET_NAME BACKEND_NAME; do
    [ -z "$BACKEND_NAME" ] && continue
    BACKEND_WEIGHT=$(oci lb backend get --region "$ORACLE_REGION" --load-balancer-id "$BACKEND_LB_ID" --backend-set-name "$BACKEND_SET_NAME" --backend-name "$BACKEND_NAME" | jq -r '.data.weight')
    [[ "$BACKEND_WEIGHT" =~ ^[0-9]+$ ]] || BACKEND_WEIGHT=1
    echo -e "\n## rotate-nomad-poool-oracle: draining $BACKEND_NAME in $BACKEND_SET_NAME"
    BACKEND_STATE=$(oci lb backend update --region "$ORACLE_REGION" --load-balancer-id "$BACKEND_LB_ID" --backend-set-name "$BACKEND_SET_NAME" --backend-name "$BACKEND_NAME" \
        --weight "$BACKEND_WEIGHT" --backup false --drain true --offline false --wait-for-state SUCCEEDED --wait-for-state FAILED | jq -r '.data."lifecycle-state"')
    if [ "$BACKEND_STATE" != "SUCCEEDED" ]; then
      echo "## WARNING: could not drain $BACKEND_NAME in $BACKEND_SET_NAME (work request state: ${BACKEND_STATE:-none})"
    fi
  done <<< "$LB_DRAIN_BACKENDS"

  echo -e "\n## rotate-nomad-poool-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and shutting down nomad and consul nicely"
  # first set old instances ineligible and capture node IDs for later purge
  DETACHABLE_NODE_IDS=""
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: marking nomad node ineligible on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node eligibility -self -disable"
    NODE_ID=$(timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP \
      "nomad node status -self -json 2>/dev/null | jq -r .ID" 2>/dev/null)
    if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ]; then
      DETACHABLE_NODE_IDS="$DETACHABLE_NODE_IDS $NODE_ID"
      echo -e "\n## rotate-nomad-poool-oracle: captured node ID $NODE_ID for $IP"
    else
      echo -e "\n## rotate-nomad-poool-oracle: WARNING: could not get node ID for $IP"
    fi
  done
  sleep 90
  # next drain old instances
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: draining nomad node on $IP"
    if ! timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node drain -self -enable -no-deadline -detach -yes"; then
      echo "## WARNING: could not start nomad drain on $IP"
    fi
  done
  echo -e "\n## rotate-nomad-poool-oracle: waiting for nomad drain to complete before stopping nomad and consul"
  # Stopping consul mid-drain deregisters the services of allocs still waiting to migrate, so the last
  # copy of a service (alloy) can vanish before its replacement is healthy.
  WAIT_TOTAL=0
  for IP in $DETACHABLE_IPS; do
    while true; do
      # A drain that never started also has no DrainStrategy, so only LastDrain proves it finished.
      DRAIN_STATE=$(timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP \
        "nomad node status -self -json 2>/dev/null | jq -r 'if .DrainStrategy != null then \"draining\" else (.LastDrain.Status // \"never drained\") end'" 2>/dev/null)
      [ "$DRAIN_STATE" == "complete" ] && break
      if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
        echo "## WARNING: nomad drain on $IP not complete (state: ${DRAIN_STATE:-query failed}) within $MAX_WAIT_SECONDS seconds, stopping anyway"
        break
      fi
      echo "Waiting for nomad drain to complete on $IP (state: ${DRAIN_STATE:-query failed})"
      sleep $WAIT_INTERVAL_SECONDS
      WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
    done
  done
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: stopping nomad and consul on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "sudo service nomad stop && sudo service consul stop"
  done

  # purge detached nodes from Nomad cluster state so system jobs don't show unplaced
  if [ -n "$DETACHABLE_NODE_IDS" ]; then
    [ -z "$NOMAD_ADDR" ] && export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
    for NODE_ID in $DETACHABLE_NODE_IDS; do
      echo -e "\n## rotate-nomad-poool-oracle: purging nomad node $NODE_ID"
      # check curl's own status: piped straight into jq, a failed request exits 0 and prints nothing
      PURGE_RESPONSE=$(curl -sf -X POST "$NOMAD_ADDR/v1/node/$NODE_ID/purge")
      if [ $? -eq 0 ] && echo "$PURGE_RESPONSE" | jq -e 'has("NodeModifyIndex")' > /dev/null 2>&1; then
        echo "$PURGE_RESPONSE" | jq -r '"purged, eval \(.EvalIDs[0] // "none")"'
      else
        echo "## WARNING: purge request to $NOMAD_ADDR failed for node $NODE_ID"
      fi
    done
  fi

  # scale down the old instances
  echo -e "\n## rotate-nomad-poool-oracle: halve the size of nomad instance pool"
  ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py halve --wait

fi