#!/bin/bash

set -x

echo "# starting rotate-consul-oracle.sh"

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

if [ -z "$ENVIRONMENT" ]; then
  echo "## ERROR: rotate-consul-oracle must have ENVIRONMENT set; exiting..."
  exit 2
fi

# pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "## ERROR: rotate-consul-oracle must have ORACLE_REGION set; exiting..."
  exit 2
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/"${ORACLE_CLOUD_NAME}".sh

TAG_NAMESPACE="jitsi"

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type JammyBase --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "## image not found via oracle_custom_images.py; exiting..."
  exit 1
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-consul"
[ -z "$INSTANCE_POOL_BASE_NAME" ] && INSTANCE_POOL_BASE_NAME="ConsulInstancePool"

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_CONSUL_SHAPE"
if [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi
if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi

# by default wait 5 minutes in between rotating consul instances
[ -z "$STARTUP_GRACE_PERIOD_SECONDS" ] && STARTUP_GRACE_PERIOD_SECONDS=300

# iterate across the three instance pools
for x in {a..c}; do
  INSTANCE_POOL_NAME=$INSTANCE_POOL_BASE_NAME-$x

  INSTANCE_POOL_DETAILS=$(oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --lifecycle-state RUNNING --all --display-name "$INSTANCE_POOL_NAME" | jq .data[0])
  if [ -z "$INSTANCE_POOL_DETAILS" ] || [ "$INSTANCE_POOL_DETAILS" == "null" ]; then
    echo "## ERROR: no instance pool found with name $INSTANCE_POOL_NAME; exiting..."
    exit 1
  fi

  echo "## rotating consul pool $INSTANCE_POOL_NAME in cloud $ORACLE_CLOUD_NAME"

  METADATA_PATH="$LOCAL_PATH/../terraform/consul-server/user-data/postinstall-runner-oracle.sh"
  INSTANCE_POOL_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.id')

  export INSTANCE_PRE_DETACH_SCRIPT="$LOCAL_PATH/rotate-consul-pre-detach.sh"
  export INSTANCE_POST_ATTACH_SCRIPT="$LOCAL_PATH/rotate-consul-post-attach.sh"

  export ENVIRONMENT
  export ORACLE_REGION
  export COMPARTMENT_OCID
  export INSTANCE_POOL_ID
  export LOAD_BALANCER_ID
  export ORACLE_GIT_BRANCH
  export IMAGE_OCID
  export METADATA_PATH
  export SHAPE
  export OCPUS
  export MEMORY_IN_GBS

  $LOCAL_PATH/rotate-instance-pool-oracle.sh $SSH_USER

  RET=$?
  if [[ $RET -gt 0 ]]; then
    echo "## ERROR rotating $INSTANCE_POOL_NAME; bailing out"
    exit $RET
  fi

  if [[ "$x" != "c" ]]; then
    # there is only one instance per pool so this sleep has to be outside of the rotate-instance-pool-oracle loop
    echo "sleeping for $STARTUP_GRACE_PERIOD_SECONDS seconds to allow for consul to come up"
    sleep $STARTUP_GRACE_PERIOD_SECONDS
  fi
done
