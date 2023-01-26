#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

if [ -z "$DOMAIN" ]; then
   echo "No DOMAIN provided or found.  Exiting ..."
   exit 202
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

[ -z "$USER" ] && USER="ubuntu"

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"

[ -z "$USER_PRIVATE_KEY_PATH" ] && USER_PRIVATE_KEY_PATH="~/.ssh/id_rsa"

[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"
[ -z "$OCPUS" ] && OCPUS="2"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"

[ -z "$FIREZONE_NAME" ] && FIREZONE_NAME="$ORACLE_REGION-$ENVIRONMENT-vpn"

[ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$FIREZONE_NAME"

[ -z "$FIREZONE_BASE_IMAGE_ID" ] && FIREZONE_BASE_IMAGE_ID=$($LOCAL_PATH/oracle_custom_images.py --type FocalBase --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$FIREZONE_BASE_IMAGE_ID" ]; then
  echo "No FIREZONE_BASE_IMAGE_ID found.  Exiting..."
  exit 1
fi

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

RESOURCE_NAME_ROOT="${ORACLE_CLOUD_NAME}-vpn"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$FIREZONE_NAME/terraform.tfstate"

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

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="availability_domain=$AVAILABILITY_DOMAIN"\
  -var="domain=$DOMAIN"\
  -var="environment=$ENVIRONMENT"\
  -var="environment_type=$ENVIRONMENT_TYPE"\
  -var="name=$FIREZONE_NAME"\
  -var="display_name=$DISPLAY_NAME"\
  -var="oracle_region=$ORACLE_REGION"\
  -var="shape=$SHAPE"\
  -var="ocpus=$OCPUS"\
  -var="memory_in_gbs=$MEMORY_IN_GBS"\
  -var="git_branch=$ORACLE_GIT_BRANCH"\
  -var="user=ubuntu"\
  -var="dns_name=$DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH"\
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH"\
  -var="tenancy_ocid=$TENANCY_OCID"\
  -var="compartment_ocid=$COMPARTMENT_OCID"\
  -var="vcn_name=$VCN_NAME"\
  -var="subnet_ocid=$PUBLIC_SUBNET_OCID"\
  -var="security_group_ocid=$PUBLIC_SECURITY_GROUP_OCID"\
  -var="image_ocid=$FIREZONE_BASE_IMAGE_ID"\
  -var "tag_namespace=$TAG_NAMESPACE" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS

