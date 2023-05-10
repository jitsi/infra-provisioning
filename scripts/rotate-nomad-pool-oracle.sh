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

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [  -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## recycle-haproxy-oracle: ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## recycle-haproxy-oracle: run ansible as $SSH_USER"
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

  # first apply changes to instance configuration, etc
  $LOCAL_PATH/../terraform/nomad-pool/create-nomad-pool-stack.sh

  if [ $? -gt 0 ]; then
    echo -e "\n## Nomad pool configuration update failed, exiting"
    exit 5
  fi


  ORACLE_REGION=$ORACLE_REGION ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID $LOCAL_PATH/pool.py inventory

  # next scale up by 2X
  echo -e "\n## rotate-nomad-poool-oracle: double the size of nomad pool"
  ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py double --wait

  DETACHABLE_IPS=$(ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py halve --onlyip)

  echo -e "\n## rotate-nomad-poool-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and shutting down nomad and consul nicely"
  # drain old instances
  for IP in $DETACHABLE_IPS; do
    echo -e "\n## rotate-nomad-poool-oracle: draining nomad node on $IP"
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "nomad node eligibility -self -disable && nomad node drain -self -enable -force -detach -yes"
    echo -e "\n## rotate-nomad-poool-oracle: waiting for nomad drain to complete before stopping nomad and consul on $IP"
    sleep 90
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$IP "sudo service nomad stop && sudo service consul stop"
  done

  # scale down the old instances
  echo -e "\n## rotate-nomad-poool-oracle: halve the size of nomad instance pool"
  ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py halve --wait

fi