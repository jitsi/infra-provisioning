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

if [ -z "$DOMAIN" ]; then
  echo "No DOMAIN provided or found.  Exiting ..."
  exit 202
fi

[ -z "$NAME" ] && NAME="$ENVIRONMENT-jigasi.$DOMAIN"

[ -z "$SHARD_ROLE" ] && SHARD_ROLE="jigasi"

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

[ -z "$JIGASI_RELEASE_NUMBER" ] && JIGASI_RELEASE_NUMBER="0"

#if we're not given versions, search for the latest of each type of image
[ -z "$JIGASI_VERSION" ] && JIGASI_VERSION='latest'

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$CLOUD_NAME" ]; then
  echo "No CLOUD_NAME found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$JIGASI_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$DEFAULT_JIGASI_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"

if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
elif [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
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

if [[ "$JIGASI_TRANSCRIBER_FLAG" == "true" ]]; then
  # put transcribers in the NAT subnet
  INSTANCE_CONFIG_SUFFIX="TranscriberInstanceConfig"
  SHARD_ROLE="jigasi-transcriber"
  [ -z "$JIGASI_SUBNET_NAME" ] && JIGASI_SUBNET_NAME="${ORACLE_REGION}-${ENVIRONMENT}-NATSubnet"
else
  INSTANCE_CONFIG_SUFFIX="JigasiInstanceConfig"
  [ -z "$JIGASI_SUBNET_NAME" ] && JIGASI_SUBNET_NAME="${ORACLE_REGION}-${ENVIRONMENT}-JigasiSubnet"
fi

[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="$ENVIRONMENT-$SUFFIX"

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_ed25519.pub"

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type Jigasi --version "$JIGASI_VERSION" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 1
fi

[ -z "$VCN_NAME" ] && VCN_NAME="${ORACLE_REGION}-${ENVIRONMENT}-vcn"
[ -z "$JIGASI_SECURITY_GROUP_NAME" ] && JIGASI_SECURITY_GROUP_NAME="${ORACLE_REGION}-${ENVIRONMENT}-JigasiCustomSecurityGroup"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/$SHARD_ROLE/instance-config-terraform.tfstate"

rm -f terraform.tfstate
TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
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
  -var="shard_role=$SHARD_ROLE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="vcn_name=$VCN_NAME" \
  -var="subnet_name=$JIGASI_SUBNET_NAME" \
  -var="security_group_name=$JIGASI_SECURITY_GROUP_NAME" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="jigasi_release_number=$JIGASI_RELEASE_NUMBER" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="aws_cloud_name=$CLOUD_NAME" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
  RET=$?

if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
  echo "Tagging jigasi image as production"
  $LOCAL_PATH/../../scripts/oracle_custom_images.py --tag_production --image_id $IMAGE_OCID --region $ORACLE_REGION
fi

exit $RET