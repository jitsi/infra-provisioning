#!/bin/bash

set -e

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

if [ -z "$JVB_POOL_NAME" ]; then
  echo "No JVB_POOL_NAME found. Exiting..."
  exit 204
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

source $LOCAL_PATH/../clouds/all.sh

[ -z "$CLOUD_NAME" ] && CLOUD_NAME=$DEFAULT_CLOUD

source $LOCAL_PATH/../clouds/"$CLOUD_NAME".sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

# first remove the ENVIRONMENT piece from the JVB_POOL_NAME
JVB_POOL_NAME_CLEAN=${JVB_POOL_NAME//$ENVIRONMENT-/}

# now remove the last two components (mode and release number)
JVB_POOL_NAME_CLEAN=${JVB_POOL_NAME_CLEAN%-*}
JVB_POOL_NAME_CLEAN=${JVB_POOL_NAME_CLEAN%-*}

ORACLE_REGION=${JVB_POOL_NAME_CLEAN}

if [ -z "$ORACLE_REGION" ]; then
  echo "Could not parse oracle region from pool name: $JVB_POOL_NAME"
  exit 205
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

if [ -z "$ORACLE_REGION" ] || [ -z "$COMPARTMENT_OCID" ] || [ -z "$TAG_NAMESPACE" ]; then
  echo "Missing required Oracle configuration: ORACLE_REGION, COMPARTMENT_OCID, or TAG_NAMESPACE"
  exit 206
fi

# Get the autoscaler group name
GROUP_NAME="${JVB_POOL_NAME}-JVBCustomGroup"

# Get list of instances in the pool
INSTANCES=$(oci compute instance list \
  --region "$ORACLE_REGION" \
  --compartment-id "$COMPARTMENT_OCID" \
  --all \
  --query "data[?\"freeform-tags\".\"group\" == '$GROUP_NAME' && \"lifecycle-state\" != 'TERMINATED'].id" \
  --raw-output \
  | jq -r '.[]' 2>/dev/null || echo "")

if [ -z "$INSTANCES" ]; then
  echo "No instances found for pool: $JVB_POOL_NAME"
  exit 207
fi

# Get the first instance
FIRST_INSTANCE=$(echo "$INSTANCES" | head -1)

if [ -z "$FIRST_INSTANCE" ]; then
  echo "No valid instance found"
  exit 208
fi

# Get the GIT_BRANCH tag from the first instance
GIT_BRANCH=$(oci compute instance get \
  --region "$ORACLE_REGION" \
  --instance-id "$FIRST_INSTANCE" \
  --query "data.\"defined-tags\".\"$TAG_NAMESPACE\".\"git_branch\"" \
  --raw-output 2>/dev/null || echo "")

if [ -z "$GIT_BRANCH" ] || [ "$GIT_BRANCH" = "null" ]; then
  echo "No git_branch tag found on instance $FIRST_INSTANCE"
  exit 209
fi

echo "$GIT_BRANCH"