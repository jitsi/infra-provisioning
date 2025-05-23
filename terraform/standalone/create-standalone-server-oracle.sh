#!/usr/bin/env bash
set -x
unset SSH_USER

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="all"
[ -z "$UNIQUE_ID" ] && UNIQUE_ID="standalone"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$UNIQUE_ID"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_STANDALONE_SHAPE"
[ -z "$SHAPE" ] && SHAPE="VM.Standard.A1.Flex"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="8"
if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS="4"
else
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS="2"
fi

[ -z "$DISK_IN_GBS" ] && DISK_IN_GBS="$DISK_SIZE"
[ -z "$DISK_IN_GBS" ] && DISK_IN_GBS="50"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

RESOURCE_NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-$UNIQUE_ID"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"
[ -z "$INTERNAL_DNS_NAME" ] && INTERNAL_DNS_NAME="$RESOURCE_NAME_ROOT-internal.$DNS_ZONE_NAME"

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"

[ -z "$USER_PRIVATE_KEY_PATH" ] && USER_PRIVATE_KEY_PATH="~/.ssh/id_rsa"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/standalone/$UNIQUE_ID/terraform.tfstate"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$STANDALONE_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="JammyBase"

arch_from_shape $SHAPE

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type $BASE_IMAGE_TYPE --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 210
fi

[ -z "$AVAILABILITY_DOMAINS" ] && AVAILABILITY_DOMAINS=$(oci iam availability-domain list --region=$ORACLE_REGION | jq .data[].name | jq --slurp .)
if [ -z "$AVAILABILITY_DOMAINS" ]; then
  echo "No AVAILABILITY_DOMAINS found.  Exiting..."
  exit 206
fi


[ -z "$PUBLIC_FLAG" ] && PUBLIC_FLAG="false"

# set SUBNET_OCID based on PUBLIC_FLAG
if [[ "$PUBLIC_FLAG" == "true" ]]; then
  SUBNET_OCID="$JVB_SUBNET_OCID"
  [ -z "$INGRESS_NSG_CIDR" ] && INGRESS_NSG_CIDR="0.0.0.0/0"
else
  SUBNET_OCID="$NAT_SUBNET_OCID"
  [ -z "$INGRESS_NSG_CIDR" ] && INGRESS_NSG_CIDR="10.0.0.0/8"
fi

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"
POSTINSTALL_STATUS_FILE="/tmp/postinstall_status.txt"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS=" $LOCAL_PATH"
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
  -var="environment=$ENVIRONMENT" \
  -var="domain=$DOMAIN" \
  -var="name=$NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="shape=$SHAPE" \
  -var="instance_shape_config_memory_in_gbs=$MEMORY_IN_GBS" \
  -var="instance_shape_config_ocpus=$INSTANCE_SHAPE_OCPUS" \
  -var="disk_in_gbs=$DISK_IN_GBS" \
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="vcn_name=$VCN_NAME" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="subnet_ocid=$SUBNET_OCID" \
  -var="public_flag=$PUBLIC_FLAG" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="internal_dns_name=$INTERNAL_DNS_NAME" \
  -var="dns_name=$DNS_NAME" \
  -var="instance_display_name=$DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user=$SSH_USER" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
  -var="ingress_nsg_cidr=$INGRESS_NSG_CIDR" \
  -var="unique_id=$UNIQUE_ID" \
  -var="infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var="infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
