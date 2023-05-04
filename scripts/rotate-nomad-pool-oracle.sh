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

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

TAG_NAMESPACE="jitsi"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$NOMAD_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="JammyBase"

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"

arch_from_shape $SHAPE

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type $BASE_IMAGE_TYPE --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 210
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$ROLE" ] && ROLE="nomad-pool"
[ -z "$POOL_TYPE" ] && POOL_TYPE="general"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$POOL_TYPE"

[ -z "$NAME_ROOT" ] && NAME_ROOT="$NAME"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${NAME_ROOT}-InstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-InstanceConfig"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="32"
[ -z "$OCPUS" ] && OCPUS="8"

INSTANCE_POOL_DETAILS=$(oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --lifecycle-state RUNNING --all --display-name "$INSTANCE_POOL_NAME" | jq .data[0])
if [ -z "$INSTANCE_POOL_DETAILS" ] || [ "$INSTANCE_POOL_DETAILS" == "null" ]; then
  echo "No instance pool found with name $INSTANCE_POOL_NAME. Exiting..."
  exit 3
else
  INSTANCE_POOL_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.id')

  # first apply changes to instance configuration, etc
  $LOCAL_PATH/../terraform/nomad-pool/create-nomad-pool-stack.sh


  ORACLE_REGION=$ORACLE_REGION ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID $LOCAL_PATH/pool.py inventory

  # next scale up by 2X
  echo -e "\n## rotate-nomad-poool-oracle: double the size of nomad pool"
  ENVIRONMENT=$ENVIRONMENT ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py double --wait

  # drain old instances
  $LOCAL_PATH/rotate-nomad-pre-detach.sh

  # scale down the old instances
  DETACHABLE_IPS=$(ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py halve --onlyip)

  echo -e "\n## recycle-haproxy-oracle: shelling into detachable instances at ${DETACHABLE_IPS} and shutting down consul nicely"
  for IP in $DETACHABLE_IPS; do
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $ANSIBLE_SSH_USER@$IP "nomad node eligibility -self -disable && nomad node drain -self -enable -force -detach -yes"
    sleep 90
    timeout 10 ssh -n -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $ANSIBLE_SSH_USER@$IP "sudo service nomad stop && sudo service consul stop"
  done

  echo -e "\n## recycle-haproxy-oracle: halve the size of all haproxy instance pools"
  ENVIRONMENT=$ENVIRONMENT MINIMUM_POOL_SIZE=2 ROLE=nomad-pool INSTANCE_POOL_ID=$INSTANCE_POOL_ID ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/pool.py halve --wait

fi