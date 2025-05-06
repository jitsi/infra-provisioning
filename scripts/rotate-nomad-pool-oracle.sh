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

  echo -e "\n## rotate-nomad-poool-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and shutting down nomad and consul nicely"
  # first set old instances ineligible
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: marking nomad node ineligible on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node eligibility -self -disable"
  done
  sleep 90
  # next drain old instances
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: draining nomad node on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node drain -self -enable -no-deadline -detach -yes"
  done
  echo -e "\n## rotate-nomad-poool-oracle: waiting for nomad drain to complete before stopping nomad and consul"
  sleep 90
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: stopping nomad and consul on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "sudo service nomad stop && sudo service consul stop"
  done

  # scale down the old instances
  echo -e "\n## rotate-nomad-poool-oracle: halve the size of nomad instance pool"
  ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGIONS=$ORACLE_REGION $LOCAL_PATH/pool.py halve --wait

fi