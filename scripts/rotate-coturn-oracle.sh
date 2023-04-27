#!/bin/bash

#!/bin/bash
set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . ../all/clouds/"${ORACLE_CLOUD_NAME}".sh

TAG_NAMESPACE="jitsi"

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_COTURN_SHAPE"

arch_from_shape $SHAPE

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type coTURN --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 210
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-coturn"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${ENVIRONMENT}-${ORACLE_REGION}-CoturnInstancePool"

[ -z "$OCPUS" ] && OCPUS=8
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16

# by default wait 10 minutes in between rotating coturn instances
[ -z "$STARTUP_GRACE_PERIOD_SECONDS" ] && STARTUP_GRACE_PERIOD_SECONDS=600

INSTANCE_POOL_DETAILS=$(oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --lifecycle-state RUNNING --all --display-name "$INSTANCE_POOL_NAME" | jq .data[0])
if [ -z "$INSTANCE_POOL_DETAILS" ] || [ "$INSTANCE_POOL_DETAILS" == "null" ]; then
  echo "No instance pool found with name $INSTANCE_POOL_NAME. Exiting..."
  exit 3
else

  METADATA_PATH="$LOCAL_PATH/terraform/create-coturn-stack/user-data/postinstall-runner-oracle.sh"
  INSTANCE_POOL_ID=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.id')
  export INCLUDE_EIP_LIB="true"

  export INSTANCE_PRE_DETACH_SCRIPT="$LOCAL_PATH/rotate-coturn-pre-detach.sh"
  export INSTANCE_POST_ATTACH_SCRIPT="$LOCAL_PATH/rotate-coturn-post-attach.sh"

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
  export STARTUP_GRACE_PERIOD_SECONDS

  $LOCAL_PATH/rotate-instance-pool-oracle.sh
  exit $?
fi