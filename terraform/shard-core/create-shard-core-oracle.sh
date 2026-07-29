#!/usr/bin/env bash
set -x
unset SSH_USER

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="core"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$SIGNAL_VERSION" ] && [ ! -z "$JICOFO_VERSION" ] && [ ! -z "$JITSI_MEET_VERSION" ] && SIGNAL_VERSION="${JICOFO_VERSION}-${JITSI_MEET_VERSION}"
[ -z "$SIGNAL_VERSION" ] && SIGNAL_VERSION='latest'

[ -z "$RELEASE_NUMBER" ] && RELEASE_NUMBER=0

[ -z "$DEFAULT_VISITORS_FACTOR" ] && DEFAULT_VISITORS_FACTOR=1
[ -z "$VISITORS_FACTOR" ] && VISITORS_FACTOR=$DEFAULT_VISITORS_FACTOR

#Default shard base name to environment name
[ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

#shard name ends up like: lonely-us-phoenix-1-s3
[ -z "$SHARD_NAME" ] && export SHARD_NAME="${SHARD_BASE}-${ORACLE_REGION}-s${SHARD_NUMBER}"

[ -z "$SHARD_NUMBER" ] && SHARD_NUMBER=$(SHARD="$SHARD_NAME" $LOCAL_PATH/../../scripts/shard.sh number)

[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

CLOUD_NAME="$ENVIRONMENT-$ORACLE_REGION"
[ -z "$SHAPE" ] && SHAPE="$DEFAULT_SIGNAL_SHAPE"
[ -z "$SHAPE" ] && SHAPE="VM.Standard.A1.Flex"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"
if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS="$SIGNAL_OCPUS"
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS=8
elif [[ "$SHAPE" == "VM.Standard.A2.Flex" ]]; then
  [ -n "$SIGNAL_OCPUS" ] && INSTANCE_SHAPE_OCPUS="$((SIGNAL_OCPUS/2))"
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS=4
else
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS="$SIGNAL_OCPUS"
  [ -z "$INSTANCE_SHAPE_OCPUS" ] && INSTANCE_SHAPE_OCPUS=4
fi
[ -z "$DISK_IN_GBS" ] && DISK_IN_GBS="50"
[ -z "$VISITORS_COUNT" ] && VISITORS_COUNT="0"

if [[ $VISITORS_FACTOR -gt 1 ]]; then
  MEMORY_IN_GBS=$((VISITORS_FACTOR*MEMORY_IN_GBS));
  INSTANCE_SHAPE_OCPUS=$((VISITORS_FACTOR*INSTANCE_SHAPE_OCPUS));
  VISITORS_COUNT="$INSTANCE_SHAPE_OCPUS"
fi

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

RESOURCE_NAME_ROOT="$SHARD_NAME"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"
[ -z "$INTERNAL_DNS_NAME" ] && INTERNAL_DNS_NAME="$RESOURCE_NAME_ROOT-internal.$DNS_ZONE_NAME"

[ -z "$ALARM_PAGERDUTY_TOPIC_NAME" ] && ALARM_PAGERDUTY_TOPIC_NAME="${ENVIRONMENT}-PagerDutyTopic"
[ -z "$ALARM_EMAIL_TOPIC_NAME" ] && ALARM_EMAIL_TOPIC_NAME="${ENVIRONMENT}-topic"

[ -z "$ENABLE_PAGERDUTY_ALARMS" ] && ENABLE_PAGERDUTY_ALARMS="false"
[ -z "$ALARM_PAGERDUTY_ENABLED" ] && ALARM_PAGERDUTY_ENABLED="$ENABLE_PAGERDUTY_ALARMS"

# leave alarms disabled until shard is fully up
[ -z "$ALARM_INITIAL_ENABLED" ] && ALARM_INITIAL_ENABLED="false"

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

[ -z "$POSTINSTALL_STATUS_FILE" ] && POSTINSTALL_STATUS_FILE="/tmp/postinstall_status.txt"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/shards/$SHARD_NAME/terraform.tfstate"

arch_from_shape $SHAPE

[ -z "$IMAGE_OCID" ] && IMAGE_OCID=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type Signal --version "$SIGNAL_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

if [ -z "$IMAGE_OCID" ]; then
  echo "No IMAGE_OCID found.  Exiting..."
  exit 210
fi

[ -z "$AVAILABILITY_DOMAINS" ] && AVAILABILITY_DOMAINS=$(oci iam availability-domain list --region=$ORACLE_REGION | jq .data[].name | jq --slurp .)
if [ -z "$AVAILABILITY_DOMAINS" ]; then
  echo "No AVAILABILITY_DOMAINS found.  Exiting..."
  exit 206
fi

[ -z "$INGRESS_NSG_CIDR" ] && INGRESS_NSG_CIDR="0.0.0.0/0"

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

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
  -var="environment=$ENVIRONMENT" \
  -var="domain=$DOMAIN" \
  -var="release_number=$RELEASE_NUMBER" \
  -var="exclusive_tenant=$EXCLUSIVE_TENANT" \
  -var="shard=$SHARD_NAME" \
  -var="shard_number=$SHARD_NUMBER" \
  -var="cloud_name=$CLOUD_NAME" \
  -var="name=$SHARD_NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="shape=$SHAPE" \
  -var="instance_shape_config_memory_in_gbs=$MEMORY_IN_GBS" \
  -var="instance_shape_config_ocpus=$INSTANCE_SHAPE_OCPUS" \
  -var="disk_in_gbs=$DISK_IN_GBS" \
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="vcn_name=$VCN_NAME" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="subnet_ocid=$JVB_SUBNET_OCID" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="internal_dns_name=$INTERNAL_DNS_NAME" \
  -var="dns_name=$DNS_NAME" \
  -var="instance_display_name=$DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="alarm_pagerduty_topic_name=$ALARM_PAGERDUTY_TOPIC_NAME" \
  -var="alarm_email_topic_name=$ALARM_EMAIL_TOPIC_NAME" \
  -var="alarm_pagerduty_is_enabled=$ALARM_PAGERDUTY_ENABLED" \
  -var="alarm_is_enabled=$ALARM_INITIAL_ENABLED" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user=$SSH_USER" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
  -var="ingress_nsg_cidr=$INGRESS_NSG_CIDR" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS

RET=$?

if [[ $RET -eq 0 ]]; then
  if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
    echo "Tagging signal image as production"
    $LOCAL_PATH/../../scripts/oracle_custom_images.py --tag_production --image_id $IMAGE_OCID --region $ORACLE_REGION
  fi
else
  echo "Shard create terraform failed."
fi

exit $RET
