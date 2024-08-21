#!/bin/bash
set -x
unset SSH_USER

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e $LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh

[ -z "$ROLE" ] && ROLE="consul"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_CONSUL_SHAPE"
if [[ "$SHAPE" == "VM.Standard.E5.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=2
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi
if [[ "$SHAPE" == "VM.Standard.E4.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=2
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi
if [[ "$SHAPE" == "VM.Standard.E3.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=2
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi
if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=4
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi
if [[ "$SHAPE" == "VM.Standard.A2.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS=2
  [ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS=16
fi

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=1

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="ConsulInstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="ConsulInstanceConfig"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

[ -z "$ENCRYPTED_CREDENTIALS_FILE" ] && ENCRYPTED_CREDENTIALS_FILE="$LOCAL_PATH/../../ansible/secrets/ssl-certificates.yml"
[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../../.vault-password.txt"

if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
    echo "No VAULT_PASSWORD_FILE found. Exiting..."
  exit 211
fi

if [ -z "$SSL_CERTIFICATE_ID" ]; then
  echo "No SSL_CERTIFICATE_ID found. Exiting..."
  exit 208
fi

[ -z "$CONSUL_CERTIFICATE_NAME_VARIABLE" ] && CONSUL_CERTIFICATE_NAME_VARIABLE="jitsi_net_ssl_name"
[ -z "$CONSUL_CA_CERTIFICATE_VARIABLE" ] && CONSUL_CA_CERTIFICATE_VARIABLE="jitsi_net_ssl_extras"
[ -z "$CONSUL_PUBLIC_CERTIFICATE_VARIABLE" ] && CONSUL_PUBLIC_CERTIFICATE_VARIABLE="jitsi_net_ssl_certificate"
[ -z "$CONSUL_PRIVATE_KEY_VARIABLE" ] && CONSUL_PRIVATE_KEY_VARIABLE="jitsi_net_ssl_key_name"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
CA_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${CONSUL_CA_CERTIFICATE_VARIABLE}" -)
PUBLIC_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${CONSUL_PUBLIC_CERTIFICATE_VARIABLE}" -)
PRIVATE_KEY=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${CONSUL_PRIVATE_KEY_VARIABLE}" -)
CONSUL_CERTIFICATE_NAME=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${CONSUL_CERTIFICATE_NAME_VARIABLE}" -)
set +e
set +o pipefail

# export private key to variable instead of outputting on command line
export TF_VAR_certificate_public_certificate="$PUBLIC_CERTIFICATE"
export TF_VAR_certificate_private_key="$PRIVATE_KEY"
export TF_VAR_certificate_ca_certificate="$CA_CERTIFICATE"

set -x

RESOURCE_NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-consul"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"

[ -z "$CONSUL_HOSTNAME" ] && CONSUL_HOSTNAME="$RESOURCE_NAME_ROOT.$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$NOMAD_HOSTNAME" ] && NOMAD_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$LOAD_BALANCER_SHAPE" ] && LOAD_BALANCER_SHAPE="flexible"

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

[ -z "$INGRESS_CIDR" ] && INGRESS_CIDR="10.0.0.0/8"

[ -z "$USER_PUBLIC_KEY_PATH" ] && USER_PUBLIC_KEY_PATH="~/.ssh/id_ed25519.pub"

[ -z "$USER_PRIVATE_KEY_PATH" ] && USER_PRIVATE_KEY_PATH="~/.ssh/id_ed25519"

if [ ! -f "$USER_PUBLIC_KEY_PATH" ]; then
    echo "USER_PUBLIC_KEY_PATH file missing at $USER_PUBLIC_KEY_PATH, exiting."
  exit 220
fi

if [ ! -f "$USER_PRIVATE_KEY_PATH" ]; then
    echo "USER_PRIVATE_KEY_PATH file missing at $USER_PRIVATE_KEY_PATH, exiting."
  exit 221
fi

[ -z "$POSTINSTALL_STATUS_FILE" ] && POSTINSTALL_STATUS_FILE="/tmp/postinstall_status.txt"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/consul/terraform.tfstate"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$CONSUL_BASE_IMAGE_TYPE"
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

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

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
  -var="environment=$ENVIRONMENT" \
  -var="name=$NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="shape=$SHAPE" \
  -var="ocpus=$OCPUS" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="vcn_name=$VCN_NAME" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="load_balancer_shape=$LOAD_BALANCER_SHAPE" \
  -var="subnet_ocid=$NAT_SUBNET_OCID" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="ingress_cidr=$INGRESS_CIDR" \
  -var="instance_pool_size=$INSTANCE_POOL_SIZE" \
  -var="instance_pool_name=$INSTANCE_POOL_NAME" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="dns_name=$DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user=$SSH_USER" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
  -var="certificate_certificate_name=$CONSUL_CERTIFICATE_NAME" \
  -var="consul_hostname=$CONSUL_HOSTNAME" \
  -var="nomad_hostname=$NOMAD_HOSTNAME" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
