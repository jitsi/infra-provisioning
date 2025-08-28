#!/bin/bash
#set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

echo "## starting rotate-instance-pool-oracle.sh"

if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "## ssh user not defined, using current user: $SSH_USER"
else
  SSH_USER=$1
  echo "## will ssh as $SSH_USER"
fi

# We need an environment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION provided or found. Exiting .."
  exit 202
fi

if [ -z "$COMPARTMENT_OCID" ]; then
  echo "No COMPARTMENT_OCID provided or found. Exiting .."
  exit 202
fi

TAG_NAMESPACE="jitsi"

if [ -z "$INSTANCE_POOL_ID" ]; then
  echo "No INSTANCE_POOL_ID provided or found. Exiting .."
  exit 202
fi

if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 202
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

if [ -z "$METADATA_PATH" ]; then
  echo "No METADATA_PATH provided or found. Exiting .."
  exit 202
fi

[ -z "$METADATA_LIB_PATH" ] && METADATA_LIB_PATH="$LOCAL_PATH/../terraform/lib"

if [ -z "$SHAPE" ]; then
  echo "No SHAPE provided or found. Exiting .."
  exit 202
fi

if [ -z "$OCPUS" ]; then
  echo "No OCPUS provided or found. Exiting .."
  exit 202
fi

if [ -z "$MEMORY_IN_GBS" ]; then
  echo "No MEMORY_IN_GBS provided or found. Exiting .."
  exit 202
fi

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub

[ -z "$MAX_WAIT_SECONDS" ] && MAX_WAIT_SECONDS=1200 # 20 min
[ -z "$WAIT_INTERVAL_SECONDS" ] && WAIT_INTERVAL_SECONDS=30

# if no load balancer is available to detect bootup health then
# wait a fixed period between instances when rotating
[ -z "$STARTUP_GRACE_PERIOD_SECONDS" ] && STARTUP_GRACE_PERIOD_SECONDS=300 # 5 min

SHAPE_PARAMS=
[ ! -z "$SHAPE" ] && SHAPE_PARAMS="$SHAPE_PARAMS --shape $SHAPE"
[ ! -z "$OCPUS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --ocpus $OCPUS"
[ ! -z "$MEMORY_IN_GBS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --memory $MEMORY_IN_GBS"

echo "Take an inventory of the existing instances in pool"
EXISTING_INSTANCE_DATA=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_OCID" --instance-pool-id "$INSTANCE_POOL_ID" --region "$ORACLE_REGION" --all)
EXISTING_INSTANCES="$(echo "$EXISTING_INSTANCE_DATA" | jq .data)"
INSTANCE_COUNT=$(echo $EXISTING_INSTANCES| jq -r ".|length")

export DESIRED_CAPACITY=$INSTANCE_COUNT

echo "Rotating instance pool $INSTANCE_POOL_ID"
export ROTATE_INSTANCE_POOL=true
if [ ! -z "$ROTATE_INSTANCE_CONFIGURATION_SCRIPT" ]; then
  echo "Running provided rotation script $ROTATE_INSTANCE_CONFIGURATION_SCRIPT"
  # source this script in case any variables need to be used that were set in the pre script
  . $ROTATE_INSTANCE_CONFIGURATION_SCRIPT $SSH_USER
else
  echo "Rotating the instance configuration of the instance pool using default rotation python"
  [ "$INCLUDE_EIP_LIB" == "true" ] && METADATA_EIP_FLAG="--metadata_eip"
  $LOCAL_PATH/rotate_instance_configuration_oracle.py \
    --region "$ORACLE_REGION" --image_id "$IMAGE_OCID" \
    --infra_customizations_repo "$INFRA_CUSTOMIZATIONS_REPO" --infra_configuration_repo "$INFRA_CONFIGURATION_REPO" \
    --git_branch "$ORACLE_GIT_BRANCH" \
    --instance_pool_id "$INSTANCE_POOL_ID" \
    --tag_namespace "$TAG_NAMESPACE" \
    --user_public_key_path "$USER_PUBLIC_KEY_PATH" \
    $METADATA_EIP_FLAG --metadata_lib_path "$METADATA_LIB_PATH" --metadata_path "$METADATA_PATH" $SHAPE_PARAMS
fi

ROTATE_IC_RESULT_CODE=$?
if [ "$ROTATE_IC_RESULT_CODE" -ne 0 ]; then
  echo "Failed rotating the instance configuration of the instance pool $INSTANCE_POOL_ID"
  exit $ROTATE_IC_RESULT_CODE
fi

if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
  echo "Tagging image as production"
  $LOCAL_PATH/oracle_custom_images.py --tag_production --image_id $IMAGE_OCID --region $ORACLE_REGION
fi



if [[ $INSTANCE_COUNT -gt 0 ]]; then
  # more than local region found, check/perform association
  for i in `seq 0 $((INSTANCE_COUNT-1))`; do
    DETAILS="$(echo "$EXISTING_INSTANCES" | jq ".[$i]")"
    INSTANCE_ID="$(echo "$DETAILS"  | jq -r ".id")"

    #make available variables to pre and post scripts
    export COMPARTMENT_OCID
    export ORACLE_REGION
    export INSTANCE_POOL_ID
    export INSTANCE_ID
    export DETAILS
    export SSH_USER
    if [ ! -z "$INSTANCE_PRE_DETACH_SCRIPT" ]; then
      # source this script in case any variables need to be set between pre and post stages
      . $INSTANCE_PRE_DETACH_SCRIPT $SSH_USER
    fi

    # look up current load balancer, use if defined
    LOAD_BALANCER_ID=$(echo "$DETAILS"  | jq -r '."load-balancer-backends"|first|."load-balancer-id"')
    [[ "$LOAD_BALANCER_ID" == "null" ]] && LOAD_BALANCER_ID=

    if [ -z "$LB_BACKEND_SET_NAME" ]; then
      LB_BACKEND_SET_NAME=$(echo "$DETAILS"  | jq -r '."load-balancer-backends"|first|."backend-set-name"')
      [[ "$LB_BACKEND_SET_NAME" == "null" ]] && LB_BACKEND_SET_NAME=
    fi

    # if an existing LB is found, update expected count based on existing count
    if [ -n "$LOAD_BALANCER_ID" ]; then
      LATEST_LB_BACKEND_HEALTH=$(oci lb backend-set-health get --region "$ORACLE_REGION" --backend-set-name "$LB_BACKEND_SET_NAME" --load-balancer-id "$LOAD_BALANCER_ID")
      EXPECTED_COUNT="$(echo $LATEST_LB_BACKEND_HEALTH | jq -r '.data."total-backend-count"')"
    fi

    # Detach with is-decrement-size false and is-auto-terminate true results in automatic creation of 4 work requests, in order:
    # 1) if LB defined - detaching from the LB
    # 2) detaching from the Instance Pool
    # 3) attaching a new instance to the Instance Pool
    # 4) if LB defined - attaching the new instance to the LB
    echo "Replacing instance $i - $INSTANCE_ID - with a new one, using the latest instance config"
    REPLACE_RESULT=$(oci compute-management instance-pool-instance detach --region "$ORACLE_REGION" --instance-id "$INSTANCE_ID" --instance-pool-id "$INSTANCE_POOL_ID" \
      --is-auto-terminate true --is-decrement-size false \
      --max-wait-seconds "$MAX_WAIT_SECONDS" --wait-interval-seconds "$WAIT_INTERVAL_SECONDS" --wait-for-state "SUCCEEDED" --wait-for-state "FAILED")
    REPLACE_RESULT_CODE=$?

    if [ "$REPLACE_RESULT_CODE" -ne 0 ]; then
      echo "Failed replacing instance $INSTANCE_ID in instance pool $INSTANCE_POOL_ID. Please try again later"
      exit 220
    fi

    REPLACE_STATUS=$(echo "$REPLACE_RESULT" | jq -r '.data.status')
    if [ "$REPLACE_STATUS" != "SUCCEEDED" ]; then
      echo "Failed replacing instance $INSTANCE_ID in instance pool $INSTANCE_POOL_ID, final status is $REPLACE_STATUS. Please try again later."
      exit 221
    fi

    # wait at least 30 seconds for instance pool state to be updated after detach
    echo "Waiting for instance pool state to be updated"
    sleep 30

    # REPLACE_STATUS value SUCCEEDED means the detach operations (1 and 2) succeeded, not the scaling up operations
    # Check instance pool has done scaling up before operating again on the pool, so as to avoid the error: instancepool ... Must be in State 'Running'
    WAIT_TOTAL=0
    LATEST_INSTANCE_POOL_STATE=$(oci compute-management instance-pool get --region "$ORACLE_REGION" --instance-pool-id "$INSTANCE_POOL_ID" | jq -r '.data["lifecycle-state"]')
    while [ "$LATEST_INSTANCE_POOL_STATE" != 'RUNNING' ]; do
      if [ $WAIT_TOTAL -gt $MAX_WAIT_SECONDS ]; then
        echo "Exceeding max waiting time of $MAX_WAIT_SECONDS seconds for instance pool to reach RUNNING, current state is $LATEST_INSTANCE_POOL_STATE. Something could be wrong, exiting..."
        exit 222
      fi

      echo "Waiting for the instance pool to reach RUNNING state again. Current state is $LATEST_INSTANCE_POOL_STATE."
      sleep $WAIT_INTERVAL_SECONDS
      WAIT_TOTAL=$((WAIT_TOTAL + WAIT_INTERVAL_SECONDS))
      LATEST_INSTANCE_POOL_STATE=$(oci compute-management instance-pool get --region "$ORACLE_REGION" --instance-pool-id "$INSTANCE_POOL_ID" | jq -r '.data["lifecycle-state"]')
    done

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
    if [ ! -z "$INSTANCE_POST_ATTACH_SCRIPT" ]; then
      # source this script in case any variables need to be used that were set in the pre script
      . $INSTANCE_POST_ATTACH_SCRIPT $SSH_USER
    fi

  done
else
  echo "No instances found to rotate in $INSTANCE_POOL_ID, skipping rotation step"
fi

echo "Successfully upgraded and rotated the instance pool $INSTANCE_POOL_ID having $INSTANCE_COUNT instances"