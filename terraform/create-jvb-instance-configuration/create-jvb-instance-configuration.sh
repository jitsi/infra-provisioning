#!/bin/bash
set -x #echo on
#!/usr/bin/env bash
unset SSH_USER

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT provided or found.  Exiting ..."
  exit 201
fi

if [ -z "$DOMAIN" ]; then
  echo "No DOMAIN provided or found.  Exiting ..."
  exit 202
fi

if [ -z "$SHARD" ]; then
  echo "No SHARD found.  Exiting..."
  exit 204
fi

[ -z "$USE_EIP" ] && USE_EIP="false"

[ -z "$NAME" ] && NAME="$SHARD-jvb.$DOMAIN"

[ -z "$SHARD_ROLE" ] && SHARD_ROLE="JVB"

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER="0"

[ -z "$JVB_RELEASE_NUMBER" ] && JVB_RELEASE_NUMBER="0"

#if we're not given versions, search for the latest of each type of image
[ -z "$JVB_VERSION" ] && JVB_VERSION='latest'

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

[ -z "$INFRA_CONFIGURATION_REPO" ] && INFRA_CONFIGURATION_REPO="$PRIVATE_CONFIGURATION_REPO"
[ -z "$INFRA_CONFIGURATION_REPO" ] && INFRA_CONFIGURATION_REPO="https://github.com/jitsi/infra-configuration.git"

[ -z "$INFRA_CUSTOMIZATIONS_REPO" ] && INFRA_CUSTOMIZATIONS_REPO="$PRIVATE_CUSTOMIZATIONS_REPO"
[ -z "$INFRA_CUSTOMIZATIONS_REPO" ] && INFRA_CUSTOMIZATIONS_REPO="https://github.com/jitsi/infra-customizations.git"

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$CLOUD_NAME" ]; then
  echo "No CLOUD_NAME found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$ENABLE_E_4" ] && ENABLE_E_4="false"

if [ "$ENABLE_E_4" == "true" ]; then
  JVB_SHAPE="$SHAPE_E_4"
fi

# use A1 if configured
if [ "$ENABLE_A_1" == "true" ]; then
  JVB_SHAPE="$SHAPE_A_1"
fi

[ -z "$SHAPE" ] && SHAPE="$JVB_SHAPE"

if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
elif [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
elif [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=8
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=12
else
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=60
fi

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="$JVB_DEFAULT_AUTOSCALER_ENABLED"
[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="true"

JVB_NOMAD_VARIABLE="jvb_enable_nomad"

[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../../config/vars.yml"
[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../../sites/$ENVIRONMENT/vars.yml"

if [ -z "$NOMAD_JVB_FLAG" ]; then
  NOMAD_JVB_FLAG="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
  if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
    NOMAD_JVB_FLAG="$(cat $CONFIG_VARS_FILE | yq eval .${JVB_NOMAD_VARIABLE} -)"
  fi
  if [[ "$NOMAD_JVB_FLAG" == "null" ]]; then
    NOMAD_JVB_FLAG=
  fi
fi
[ -z "$NOMAD_JVB_FLAG" ] && NOMAD_JVB_FLAG="false"

JVB_IMAGE_TYPE="JVB"

if [[ "$NOMAD_JVB_FLAG" == "true" ]]; then
  JVB_IMAGE_TYPE="JammyBase"
  JVB_VERSION="latest"
  SHARD_ROLE="JVB-nomad-pool"
fi

[ -z "$JVB_POOL_MODE" ] && JVB_POOL_MODE="shard"

[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="$SHARD-JVBInstanceConfig"

[ -z "$SECONDARY_VNIC_NAME" ] && SECONDARY_VNIC_NAME="${ENVIRONMENT}-${ORACLE_REGION}-SecondaryVnic"

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_ed25519.pub"

arch_from_shape $SHAPE

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type $JVB_IMAGE_TYPE --version "$JVB_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 1
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/$SHARD/instance-config-terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi
#The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure $TF_POST_PARAMS

[ -z "$ACTION" ] && ACTION="apply"
if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="domain=$DOMAIN" \
  -var="environment=$ENVIRONMENT" \
  -var="name=$NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="shape=$SHAPE" \
  -var="ocpus=$OCPUS" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="shard=$SHARD" \
  -var="shard_role=$SHARD_ROLE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="subnet_ocid=$JVB_SUBNET_OCID" \
  -var="private_subnet_ocid=$NAT_SUBNET_OCID" \
  -var="security_group_ocid=$JVB_SECURITY_GROUP_OCID" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="release_number=$RELEASE_NUMBER" \
  -var="jvb_release_number=$JVB_RELEASE_NUMBER" \
  -var="jvb_pool_mode=$JVB_POOL_MODE" \
  -var="xmpp_host_public_ip_address=$XMPP_HOST_PUBLIC_IP_ADDRESS" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="aws_cloud_name=$CLOUD_NAME" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="secondary_vnic_name=$SECONDARY_VNIC_NAME" \
  -var="use_eip=$USE_EIP" \
  -var="nomad_flag=$NOMAD_JVB_FLAG" \
  -var="autoscaler_sidecar_jvb_flag=$JVB_AUTOSCALER_ENABLED" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
RET=$?

if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
  echo "Tagging JVB image as production"
  $LOCAL_PATH/../../scripts/oracle_custom_images.py --tag_production --image_id $IMAGE_OCID --region $ORACLE_REGION
fi

exit $RET