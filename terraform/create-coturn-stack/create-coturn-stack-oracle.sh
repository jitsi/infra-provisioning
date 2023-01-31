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

#load cloud defaults
[ -e $LOCAL_PATH/../../clouds/all.sh ] && . $LOCAL_PATH/../../clouds/all.sh

# We need an envirnment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_COTURN_SHAPE"
[ -z "$OCPUS" ] && OCPUS=8
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub

#required 8x8 tag
[ -z "$SERVICE" ] && SERVICE="$DOMAIN"
[ -z "$SERVICE" ] && SERVICE="jitsi-coturn"

#Look up images based on version, or default to latest
[ -z "$COTURN_IMAGE_OCID" ] && COTURN_IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type coTURN --version "latest" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

#No image was found, probably not built yet?
if [ -z "$COTURN_IMAGE_OCID" ]; then
  echo "No COTURN_IMAGE_OCID provided or found. Exiting.. "
  exit 210
fi

[ -z "$DESIRED_CAPACITY" ] && DESIRED_CAPACITY="2"

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

# e.g. AVAILABILITY_DOMAINS='[  "ObqI:EU-FRANKFURT-1-AD-1", "ObqI:EU-FRANKFURT-1-AD-2", "ObqI:EU-FRANKFURT-1-AD-3" ]'
[ -z "$AVAILABILITY_DOMAINS" ] && AVAILABILITY_DOMAINS=$(oci iam availability-domain list --region=$ORACLE_REGION | jq .data[].name | jq --slurp .)
if [ -z "$AVAILABILITY_DOMAINS" ]; then
  echo "No AVAILABILITY_DOMAINS found.  Exiting..."
  exit 206
fi

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

SHARD_ROLE="coturn"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-coturn"

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_ed25519.pub"
[ -z "$USER_PRIVATE_KEY_PATH" ] && USER_PRIVATE_KEY_PATH="~/.ssh/id_ed25519"
[ -z "$BASTION_HOST" ] && BASTION_HOST="$CONNECTION_SSH_BASTION_HOST"
[ -z "$COTURNS_POSTINSTALL_STATUS_FILE" ] && COTURNS_POSTINSTALL_STATUS_FILE="/tmp/${NAME}_postinstall_status.txt"

[ -z "$SECONDARY_VNIC_NAME" ] && SECONDARY_VNIC_NAME="${ENVIRONMENT}-${ORACLE_REGION}-SecondaryVnic"
[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${ENVIRONMENT}-${ORACLE_REGION}-CoturnInstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${ENVIRONMENT}-${ORACLE_REGION}-CoturnInstanceConfig"
[ -z "$AUTO_SCALING_CONFIG_NAME" ] && AUTO_SCALING_CONFIG_NAME="${ENVIRONMENT}-${ORACLE_REGION}-CoturnAutoScaleConfig"
[ -z "$POLICY_NAME" ] && POLICY_NAME="${ENVIRONMENT}-${ORACLE_REGION}-CoturnScalingPolicy"
[ -z "$SCALE_IN_RULE_NAME" ] && SCALE_IN_RULE_NAME="${ENVIRONMENT}-${ORACLE_REGION}-scalingLowLoad"
[ -z "$SCALE_OUT_RULE_NAME" ] && SCALE_OUT_RULE_NAME="${ENVIRONMENT}-${ORACLE_REGION}-scalingHighLoad"

# add bastion hosts to known hosts if not present
grep -q "$BASTION_HOST" ~/.ssh/known_hosts || ssh-keyscan -H $BASTION_HOST >> ~/.ssh/known_hosts

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/coturns/$NAME/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
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
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="bastion_host=$BASTION_HOST" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="shape=$SHAPE" \
  -var="ocpus=$OCPUS" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="public_subnet_ocid=$PUBLIC_SUBNET_2_OCID" \
  -var="private_subnet_ocid=$NAT_SUBNET_OCID" \
  -var="secondary_vnic_name=$SECONDARY_VNIC_NAME" \
  -var="image_ocid=$COTURN_IMAGE_OCID" \
  -var="instance_pool_size=$DESIRED_CAPACITY" \
  -var="instance_pool_name=$INSTANCE_POOL_NAME" \
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="environment=$ENVIRONMENT" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="domain=$DOMAIN" \
  -var="name=$NAME" \
  -var="shard_role=$SHARD_ROLE" \
  -var="auto_scaling_config_name=$AUTO_SCALING_CONFIG_NAME" \
  -var="scale_out_rule_name=$SCALE_OUT_RULE_NAME" \
  -var="scale_in_rule_name=$SCALE_IN_RULE_NAME" \
  -var="policy_name=$POLICY_NAME" \
  -var="vcn_name=$VCN_NAME" \
  -var="resource_name_root=$VCN_NAME_ROOT" \
  -var="user=$SSH_USER" \
  -var="coturns_postinstall_status_file=$COTURNS_POSTINSTALL_STATUS_FILE" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
  RET=$?

if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
  echo "Tagging coturn image as production"
  $LOCAL_PATH/../../scripts/oracle_custom_images.py --tag_production --image_id $COTURN_IMAGE_OCID --region $ORACLE_REGION
fi

exit $RET