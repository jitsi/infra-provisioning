#!/bin/bash

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# We need an environment
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

CLOUD_PROVIDER="oracle"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$CLOUD_NAME" ]; then
  echo "No aws CLOUD_NAME found.  Exiting..."
  exit 204
fi

[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh"

# assume we are not a transcriber unless flag is set
[ -z "$JIGASI_TRANSCRIBER_FLAG" ] && JIGASI_TRANSCRIBER_FLAG="false"

#if we're not given versions, search for the latest of each type of image
[ -z "$JIGASI_VERSION" ] && JIGASI_VERSION='latest'

[ -z "$SHAPE" ] && SHAPE="$JIGASI_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$DEFAULT_JIGASI_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"

arch_from_shape $SHAPE

#Look up images based on version, or default to latest
[ -z "$JIGASI_IMAGE_OCID" ] && JIGASI_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type Jigasi --version "$JIGASI_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

#No image was found, probably not built yet?
if [ -z "$JIGASI_IMAGE_OCID" ]; then
  echo "No JIGASI_IMAGE_OCID provided or found. Exiting.. "
  exit 210
fi

if [ -z "$JIGASI_RELEASE_NUMBER" ]; then
  echo "No JIGASI_RELEASE_NUMBER found.  Exiting..."
  exit 205
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"


if [ -z "$JWT_ENV_FILE" ]; then 
  if [ -z "$SIDECAR_ENV_VARIABLES" ]; then
    echo "No SIDECAR_ENV_VARIABLES provided or found. Exiting.. "
    exit 211
  fi

  JWT_ENV_FILE="/etc/jitsi/autoscaler-sidecar/$SIDECAR_ENV_VARIABLES"
fi

if [ -z "$AUTOSCALER_URL" ]; then
  echo "No AUTOSCALER_URL provided or found. Exiting.. "
  exit 212
fi

[ -z "$TOKEN" ] && TOKEN=$(JWT_ENV_FILE=$JWT_ENV_FILE /opt/jitsi/jitsi-autoscaler-sidecar/scripts/jwt.sh)

  [ -z "$TYPE" ] && TYPE="jigasi"
  if [[ "$JIGASI_TRANSCRIBER_FLAG" == "true" ]]; then
    [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="TranscriberCustomGroup"
    [ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
    [ -z "$INSTANCE_CONFIG_NAME" ] && export INSTANCE_CONFIG_NAME="$ENVIRONMENT-TranscriberInstanceConfig"
  else
    [ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT_SUFFIX="JigasiCustomGroup"
    [ -z "$GROUP_NAME" ] && GROUP_NAME="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
    [ -z "$INSTANCE_CONFIG_NAME" ] && export INSTANCE_CONFIG_NAME="$ENVIRONMENT-JigasiInstanceConfig"
  fi
  
  if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=4
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
  fi
  if [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=4
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
  fi



[ -z "$JIGASI_PROTECTED_TTL_SEC" ] && JIGASI_PROTECTED_TTL_SEC=900
METADATA_PATH="$LOCAL_PATH/../terraform/create-jigasi-instance-configuration/user-data/postinstall-runner-oracle.sh"
METADATA_LIB_PATH="$LOCAL_PATH/../terraform/lib"
[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub

echo "Retrieve instance group details for group $GROUP_NAME"
instanceGroupGetResponse=$(curl -s -w "\n %{http_code}" -X GET \
  "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
  -H "Authorization: Bearer $TOKEN")

getGroupHttpCode=$(tail -n1 <<<"$instanceGroupGetResponse" | sed 's/[^0-9]*//g') # get the last line
instanceGroupDetails=$(sed '$ d' <<<"$instanceGroupGetResponse")                 # get all but the last line which contains the status code

if [ "$getGroupHttpCode" == 404 ]; then
  echo "No group named $GROUP_NAME was found. Will create one"

  if [ -z "$INSTANCE_CONFIGURATION_ID" ]; then
    echo "No Jigasi Instance Configuration was found. Will create one"

    echo "Creating Jigasi Pool"
    $LOCAL_PATH/create-custom-jigasi-pool-oracle.sh
    if [ $? == 0 ]; then
      echo "Pool was created successfully"
      exit $?
    else
      echo "Pool failed to create correctly"
      exit 214
    fi
  fi

  # populate first with environment-based default values

[ -z "$JIGASI_ENABLE_AUTO_SCALE" ] && JIGASI_ENABLE_AUTO_SCALE=true
[ -z "$JIGASI_ENABLE_LAUNCH" ] && JIGASI_ENABLE_LAUNCH=true
[ -z "$JIGASI_ENABLE_SCHEDULER" ] && JIGASI_ENABLE_SCHEDULER=false
[ -z "$JIGASI_ENABLE_RECONFIGURATION" ] && JIGASI_ENABLE_RECONFIGURATION=true
[ -z "$JIGASI_GRACE_PERIOD_TTL_SEC" ] && JIGASI_GRACE_PERIOD_TTL_SEC=600
[ -z "$JIGASI_PROTECTED_TTL_SEC" ] && JIGASI_PROTECTED_TTL_SEC=900

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE="$DEFAULT_AUTOSCALER_JIGASI_POOL_SIZE"
[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=2
[ -z "$AUTOSCALER_JIGASI_MIN_COUNT" ] && AUTOSCALER_JIGASI_MIN_COUNT="$INSTANCE_POOL_SIZE"
[ -z "$AUTOSCALER_JIGASI_MAX_COUNT" ] && AUTOSCALER_JIGASI_MAX_COUNT=10

# If Jigasi load(stress) is higher than JIGASI_SCALE_UP_THRESHOLD, the autoscaler should scale up
[ -z "$JIGASI_SCALE_UP_THRESHOLD" ] && JIGASI_SCALE_UP_THRESHOLD=0.3
# If Jigasi load(stress) is lower than JIGASI_SCALE_DOWN_THRESHOLD, the autoscaler should scale down
[ -z "$JIGASI_SCALE_DOWN_THRESHOLD" ] && JIGASI_SCALE_DOWN_THRESHOLD=0.1

# scale up by 1 at a time by default unless overridden
[ -z "$JIGASI_SCALING_INCREASE_RATE" ] && JIGASI_SCALING_INCREASE_RATE=1
# scale down by 1 at a time unless overridden
[ -z "$JIGASI_SCALING_DECREASE_RATE" ] && JIGASI_SCALING_DECREASE_RATE=1

[ -z "$JIGASI_SCALE_PERIOD" ] && JIGASI_SCALE_PERIOD=60
[ -z "$JIGASI_SCALE_UP_PERIODS_COUNT" ] && JIGASI_SCALE_UP_PERIODS_COUNT=2
[ -z "$JIGASI_SCALE_DOWN_PERIODS_COUNT" ] && JIGASI_SCALE_DOWN_PERIODS_COUNT=10




  # populate with generic defaults
  [ -z "$JIGASI_MAX_COUNT" ] && JIGASI_MAX_COUNT=$AUTOSCALER_JIGASI_MAX_COUNT  
  [ -z "$JIGASI_MAX_COUNT" ] && JIGASI_MAX_COUNT=10
  [ -z "$JIGASI_MIN_COUNT" ] && JIGASI_MIN_COUNT=$AUTOSCALER_JIGASI_MIN_COUNT
  [ -z "$JIGASI_MIN_COUNT" ] && JIGASI_MIN_COUNT=1
  [ -z "$JIGASI_DOWNSCALE_COUNT" ] && JIGASI_DOWNSCALE_COUNT=1

  # ensure we don't try to downscale past minimum if minimum is overridden
  if [[ $JIGASI_DOWNSCALE_COUNT -lt $JIGASI_MIN_COUNT ]]; then
    JIGASI_DOWNSCALE_COUNT=$JIGASI_MIN_COUNT
  fi

  [ -z "$JIGASI_DESIRED_COUNT" ] && JIGASI_DESIRED_COUNT=$JIGASI_MIN_COUNT
  [ -z "$JIGASI_AVAILABLE_COUNT" ] && JIGASI_AVAILABLE_COUNT=$JIGASI_DESIRED_COUNT

  # scale up by 1 at a time by default unless overridden
  [ -z "$JIGASI_SCALING_INCREASE_RATE" ] && JIGASI_SCALING_INCREASE_RATE=1
  # scale down by 1 at a time unless overridden
  [ -z "$JIGASI_SCALING_DECREASE_RATE" ] && JIGASI_SCALING_DECREASE_RATE=1

  echo "Creating group named $GROUP_NAME"
  instanceGroupCreateResponse=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
            "name": "'"$GROUP_NAME"'",
            "type": "'$TYPE'",
            "region": "'"$ORACLE_REGION"'",
            "environment": "'"$ENVIRONMENT"'",
            "compartmentId": "'"$COMPARTMENT_OCID"'",
            "instanceConfigurationId": "'"$INSTANCE_CONFIGURATION_ID"'",
            "enableAutoScale": '$JIGASI_ENABLE_AUTO_SCALE',
            "enableLaunch": '$JIGASI_ENABLE_LAUNCH',
            "enableScheduler": '$JIGASI_ENABLE_SCHEDULER',
            "enableReconfiguration": '$JIGASI_ENABLE_RECONFIGURATION',
            "gracePeriodTTLSec": '$JIGASI_GRACE_PERIOD_TTL_SEC',
            "protectedTTLSec": '$JIGASI_PROTECTED_TTL_SEC',
            "scalingOptions": {
                "minDesired": '$JIGASI_MIN_COUNT',
                "maxDesired": '$JIGASI_MAX_COUNT',
                "desiredCount": '$JIGASI_DESIRED_COUNT',
                "scaleUpQuantity": '$JIGASI_SCALING_INCREASE_RATE',
                "scaleDownQuantity": '$JIGASI_SCALING_DECREASE_RATE',
                "scaleUpThreshold": '$JIGASI_AVAILABLE_COUNT',
                "scaleDownThreshold": '$JIGASI_DOWNSCALE_COUNT',
                "scalePeriod": '$JIGASI_SCALE_PERIOD',
                "scaleUpPeriodsCount": '$JIGASI_SCALE_UP_PERIODS_COUNT',
                "scaleDownPeriodsCount": '$JIGASI_SCALE_DOWN_PERIODS_COUNT'
            },
            "cloud": "'$CLOUD_PROVIDER'"
}')
  createGroupHttpCode=$(tail -n1 <<<"$instanceGroupCreateResponse" | sed 's/[^0-9]*//g')
  if [ "$createGroupHttpCode" == 200 ]; then
    echo "Group $GROUP_NAME was created successfully"
  else
    echo "Error creating group $GROUP_NAME. AutoScaler response status code is $createGroupHttpCode"
    exit 205
  fi

elif [ "$getGroupHttpCode" == 200 ]; then
  echo "Group $GROUP_NAME was found in the autoScaler"
  EXISTING_INSTANCE_CONFIGURATION_ID=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.instanceConfigurationId")
  EXISTING_MAXIMUM=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.maxDesired")
  if [ -z "$EXISTING_INSTANCE_CONFIGURATION_ID" ] || [ "$EXISTING_INSTANCE_CONFIGURATION_ID" == "null" ]; then
    echo "No Instance Configuration was found on the group details $GROUP_NAME. Exiting.."
    exit 206
  fi

  [ -z "$PROTECTED_INSTANCES_COUNT" ] && PROTECTED_INSTANCES_COUNT=$(echo "$instanceGroupDetails" | jq -r ."instanceGroup.scalingOptions.minDesired")
  if [ -z "$PROTECTED_INSTANCES_COUNT" ]; then
    echo "Something went wrong, could not extract PROTECTED_INSTANCES_COUNT from instanceGroup.scalingOptions.minDesired";
    exit 208
  fi

  NEW_MAXIMUM_DESIRED=$((EXISTING_MAXIMUM + PROTECTED_INSTANCES_COUNT))
  echo "Creating new Instance Configuration for group $GROUP_NAME based on the existing one"
  SHAPE_PARAMS=""
  [ ! -z "$SHAPE" ] && SHAPE_PARAMS="$SHAPE_PARAMS --shape $SHAPE"
  [ ! -z "$OCPUS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --ocpus $OCPUS"
  [ ! -z "$MEMORY_IN_GBS" ] && SHAPE_PARAMS="$SHAPE_PARAMS --memory $MEMORY_IN_GBS"

  NEW_INSTANCE_CONFIGURATION_ID=$($LOCAL_PATH/rotate_instance_configuration_oracle.py --region "$ORACLE_REGION" --image_id "$JIGASI_IMAGE_OCID" \
    --jigasi_release_number "$JIGASI_RELEASE_NUMBER" --git_branch "$ORACLE_GIT_BRANCH" \
    --infra_customizations_repo "$INFRA_CUSTOMIZATIONS_REPO" --infra_configuration_repo "$INFRA_CONFIGURATION_REPO" \
    --instance_configuration_id "$EXISTING_INSTANCE_CONFIGURATION_ID" --tag_namespace "$TAG_NAMESPACE" --user_public_key_path "$USER_PUBLIC_KEY_PATH" --metadata_lib_path "$METADATA_LIB_PATH" --metadata_path "$METADATA_PATH" --custom_autoscaler \
    $SHAPE_PARAMS)

  if [ -z "$NEW_INSTANCE_CONFIGURATION_ID" ] || [ "$NEW_INSTANCE_CONFIGURATION_ID" == "null" ]; then
    echo "No Instance Configuration was created for group $GROUP_NAME. Exiting.."
    exit 207
  fi

  echo "Old Instance Configuration id is $EXISTING_INSTANCE_CONFIGURATION_ID;
        New Instance Configuration id is $NEW_INSTANCE_CONFIGURATION_ID"

  if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
    echo "Tagging jigasi image as production"
    $LOCAL_PATH/oracle_custom_images.py --tag_production --image_id $JIGASI_IMAGE_OCID --region $ORACLE_REGION
  fi
  
  echo "Will launch $PROTECTED_INSTANCES_COUNT protected instances (new max $NEW_MAXIMUM_DESIRED) in group $GROUP_NAME"
  instanceGroupLaunchResponse=$(curl -s -w "\n %{http_code}" -X POST \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/actions/launch-protected \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
  "instanceConfigurationId": '\""$NEW_INSTANCE_CONFIGURATION_ID"'",
  "count": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '$NEW_MAXIMUM_DESIRED',
  "protectedTTLSec": '$JIGASI_PROTECTED_TTL_SEC'
}')
  launchGroupHttpCode=$(tail -n1 <<<"$instanceGroupLaunchResponse" | sed 's/[^0-9]*//g')
  if [ "$launchGroupHttpCode" == 200 ]; then
    echo "Successfully launched $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"

    echo "Will delete the old Instance Configuration for group $GROUP_NAME"
    oci compute-management instance-configuration delete --instance-configuration-id "$EXISTING_INSTANCE_CONFIGURATION_ID" --region "$ORACLE_REGION" --force
  else
    echo "Error launching $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $launchGroupHttpCode"
    exit 208
  fi

  #Wait as much as it will take to provision the new instances, before scaling down the existing ones
  sleep 600

  echo "Will scale down the group $GROUP_NAME and keep only the $PROTECTED_INSTANCES_COUNT protected instances with maximum $EXISTING_MAXIMUM"
  instanceGroupScaleDownResponse=$(curl -s -w "\n %{http_code}" -X PUT \
    "$AUTOSCALER_URL"/groups/"$GROUP_NAME"/desired \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
  "desiredCount": '"$PROTECTED_INSTANCES_COUNT"',
  "maxDesired": '"$EXISTING_MAXIMUM"'
}')
  scaleDownGroupHttpCode=$(tail -n1 <<<"$instanceGroupScaleDownResponse" | sed 's/[^0-9]*//g')
  if [ "$scaleDownGroupHttpCode" == 200 ]; then
    echo "Successfully scaled down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME"
  else
    echo "Error scaling down to $PROTECTED_INSTANCES_COUNT instances in group $GROUP_NAME. AutoScaler response status code is $scaleDownGroupHttpCode"
    exit 209
  fi

else
  echo "No group named $GROUP_NAME was found nor created. AutoScaler response status code is $getGroupHttpCode"
  exit 210
fi
