#!/bin/bash
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

if [ -z "$CLOUD_NAME" ]; then
  echo "No aws CLOUD_NAME found.  Exiting..."
  exit 204
fi

[ -e "$LOCAL_PATH/../../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${CLOUD_NAME}.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

JIBRI_NOMAD_VARIABLE="jibri_enable_nomad"

[ -z "$CONFIG_VARS_FILE" ] && CONFIG_VARS_FILE="$LOCAL_PATH/../../config/vars.yml"
[ -z "$ENVIRONMENT_VARS_FILE" ] && ENVIRONMENT_VARS_FILE="$LOCAL_PATH/../../sites/$ENVIRONMENT/vars.yml"


[ -z "$JIBRI_TYPE" ] && JIBRI_TYPE="java-jibri"
if [ "$JIBRI_TYPE" != "java-jibri" ] &&  [ "$JIBRI_TYPE" != "sip-jibri" ]; then
  echo "Unsupported jibri type $JIBRI_TYPE";
  exit 206
fi

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

[ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION"
[ -z "$NAME_ROOT" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"
[ -z "$NAME" ] && NAME="$NAME_ROOT-$JIBRI_TYPE"


[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/jibri-instance-configuration/$NAME/terraform.tfstate"

if [ "$JIBRI_TYPE" == "java-jibri" ]; then
  JIBRI_SUBNET_NAME="$VCN_NAME_ROOT-NATSubnet";
  [ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-JibriInstanceConfig"
  [ -z "$SHAPE" ] && SHAPE="$JIBRI_SHAPE"
  [ -z "$SHAPE" ] && SHAPE="$DEFAULT_JIBRI_SHAPE"

  if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=4
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
  elif [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=2
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8
  elif [[ "$SHAPE" == "VM.Standard.E5.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=2
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8
  elif [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=4
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8
  elif [[ "$SHAPE" == "VM.Standard.A2.Flex" ]]; then
    [ -z "$OCPUS" ] && OCPUS=2
    [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=8
  else
    echo "Unsupported shape $SHAPE"
    exit 207
  fi
elif [ "$JIBRI_TYPE" == "sip-jibri" ]; then
    JIBRI_SUBNET_NAME="$VCN_NAME_ROOT-SipJibriSubnet";
    [ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-SipJibriInstanceConfig"
    [ -z "$SHAPE" ] && SHAPE="$SIP_JIBRI_SHAPE"
    [ -z "$SHAPE" ] && SHAPE="$DEFAULT_SIP_JIBRI_SHAPE"

    if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
      [ -z "$OCPUS" ] && OCPUS=8
      [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    elif [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
      [ -z "$OCPUS" ] && OCPUS=8
      [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
    else
      [ -z "$OCPUS" ] && OCPUS=8
      [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=120
    fi
fi

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH=~/.ssh/id_ed25519.pub

#if we're not given versions, search for the latest of each type of image
[ -z "$JIBRI_VERSION" ] && JIBRI_VERSION='latest'

JIBRI_IMAGE_TYPE="JavaJibri"

if [ -z "$NOMAD_JIBRI_FLAG" ]; then
  NOMAD_JIBRI_FLAG="$(cat $ENVIRONMENT_VARS_FILE | yq eval .${JIBRI_NOMAD_VARIABLE} -)"
  if [[ "$NOMAD_JIBRI_FLAG" == "null" ]]; then
    NOMAD_JIBRI_FLAG="$(cat $CONFIG_VARS_FILE | yq eval .${JIBRI_NOMAD_VARIABLE} -)"
  fi

  if [[ "$NOMAD_JIBRI_FLAG" == "null" ]]; then
    NOMAD_JIBRI_FLAG="false"
  fi
fi

SHARD_ROLE="$JIBRI_TYPE"

if [[ "$NOMAD_JIBRI_FLAG" == "true" ]]; then
  JIBRI_IMAGE_TYPE="NobleBase"
  JIBRI_VERSION="latest"
  SHARD_ROLE="jibri-nomad-pool"
fi


arch_from_shape $SHAPE

#Look up images based on version, or default to latest
[ -z "$JIBRI_IMAGE_OCID" ] && JIBRI_IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type $JIBRI_IMAGE_TYPE  --version "$JIBRI_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

#No image was found, probably not built yet?
if [ -z "$JIBRI_IMAGE_OCID" ]; then
  echo "No JIBRI_IMAGE_OCID provided or found. Exiting.. "
  exit 210
fi

[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$JIBRI_RELEASE_NUMBER" ] && JIBRI_RELEASE_NUMBER=10

rm -f terraform.tfstate
#The —reconfigure option disregards any existing configuration, preventing migration of any existing state

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
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="shape=$SHAPE" \
  -var="ocpus=$OCPUS" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="vcn_name=$VCN_NAME" \
  -var="subnet_name=$JIBRI_SUBNET_NAME" \
  -var="image_ocid=$JIBRI_IMAGE_OCID" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="environment=$ENVIRONMENT" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="domain=$DOMAIN" \
  -var="name=$NAME" \
  -var="shard_role=$SHARD_ROLE" \
  -var="aws_cloud_name=$CLOUD_NAME" \
  -var="jibri_release_number=$JIBRI_RELEASE_NUMBER" \
  -var="nomad_flag=$NOMAD_JIBRI_FLAG" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS

RET=$?

if [[ "$RET" -ne 0 ]]; then
  echo "Terraform $ACTION failed with exit code $RET"
  exit $RET
fi

if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
  echo "Tagging jibri image as production"
  $LOCAL_PATH/../../scripts/oracle_custom_images.py --tag_production --image_id $JIBRI_IMAGE_OCID --region $ORACLE_REGION
fi

exit $RET