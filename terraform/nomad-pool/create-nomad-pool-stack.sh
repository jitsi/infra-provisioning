#!/usr/bin/env bash
set -x
unset SSH_USER

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="nomad-pool"
[ -z "$POOL_TYPE" ] && POOL_TYPE="general"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$POOL_TYPE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -z "$POOL_PUBLIC" ] && POOL_PUBLIC="false"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

if [ -z "$INFRA_CONFIGURATION_REPO" ]; then
  echo "No INFRA_CONFIGURATION_REPO found. Exiting..."
  exit 203
fi

if [ -z "$INFRA_CUSTOMIZATIONS_REPO" ]; then
  echo "No INFRA_CUSTOMIZATIONS_REPO found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_NOMAD_POOL_SHAPE"
[ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="64"
if [[ "$SHAPE" == "VM.Standard.A1.Flex" ]]; then
  [ -z "$OCPUS" ] && OCPUS="12"
fi

[ -z "$OCPUS" ] && OCPUS="6"
[ -z "$DISK_IN_GBS" ] && DISK_IN_GBS="100"

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=2

[ -z "$NAME_ROOT" ] && NAME_ROOT="$NAME"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${NAME_ROOT}-InstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-InstanceConfig"

RESOURCE_NAME_ROOT="${NAME_ROOT}"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

if [[ "$POOL_PUBLIC" == "true" ]]; then
  POOL_SUBNET_OCID="$PUBLIC_SUBNET_OCID"
  EPHEMERAL_INGRESS_CIDR="0.0.0.0/0"
else
  POOL_SUBNET_OCID="$NAT_SUBNET_OCID"
  EPHEMERAL_INGRESS_CIDR="10.0.0.0/8"
fi

[ -z "$ENCRYPTED_CREDENTIALS_FILE" ] && ENCRYPTED_CREDENTIALS_FILE="$LOCAL_PATH/../../ansible/secrets/ssl-certificates.yml"
[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../../.vault-password.txt"

# look up instance pool. If it exists, find its curent size and set INSTANCE_POOL_SIZE appropriately
INSTANCE_POOL_DETAILS="$(oci compute-management instance-pool list --region "$ORACLE_REGION" -c "$COMPARTMENT_OCID" --all --display-name "$INSTANCE_POOL_NAME" | jq '.data[0]')"

if [ -z "$INSTANCE_POOL_DETAILS" ] || [ "$INSTANCE_POOL_DETAILS" == "null" ]; then
  echo "No instance pool found with name $INSTANCE_POOL_NAME. Using default size $INSTANCE_POOL_SIZE..."
else
  export INSTANCE_POOL_SIZE=$(echo "$INSTANCE_POOL_DETAILS" | jq -r '.size')
  echo "Found existing instance pool with name $INSTANCE_POOL_NAME.  Using existing size $INSTANCE_POOL_SIZE"
fi

[ -z "$NOMAD_CERTIFICATE_NAME_VARIABLE" ] && NOMAD_CERTIFICATE_NAME_VARIABLE="jitsi_net_ssl_name"
[ -z "$NOMAD_CA_CERTIFICATE_VARIABLE" ] && NOMAD_CA_CERTIFICATE_VARIABLE="jitsi_net_ssl_extras"
[ -z "$NOMAD_PUBLIC_CERTIFICATE_VARIABLE" ] && NOMAD_PUBLIC_CERTIFICATE_VARIABLE="jitsi_net_ssl_certificate"
[ -z "$NOMAD_PRIVATE_KEY_VARIABLE" ] && NOMAD_PRIVATE_KEY_VARIABLE="jitsi_net_ssl_key_name"

if [[ -n "$CERTIFICATE_NAME_VARIABLE" ]]; then
  # ssl cert for domain exists in overrides
  if [[ "$CERTIFICATE_NAME_VARIABLE" != "$NOMAD_CERTIFICATE_NAME_VARIABLE" ]]; then
    # ssl cert for domain is not the same as nomad cert
    [ -z "$NOMAD_ALT_CERTIFICATE_NAME_VARIABLE" ] && NOMAD_ALT_CERTIFICATE_NAME_VARIABLE="$CERTIFICATE_NAME_VARIABLE"
    [ -z "$NOMAD_ALT_CA_CERTIFICATE_VARIABLE" ] && NOMAD_ALT_CA_CERTIFICATE_VARIABLE="$CA_CERTIFICATE_VARIABLE"
    [ -z "$NOMAD_ALT_PUBLIC_CERTIFICATE_VARIABLE" ] && NOMAD_ALT_PUBLIC_CERTIFICATE_VARIABLE="$PUBLIC_CERTIFICATE_VARIABLE"
    [ -z "$NOMAD_ALT_PRIVATE_KEY_VARIABLE" ] && NOMAD_ALT_PRIVATE_KEY_VARIABLE="$PRIVATE_KEY_VARIABLE"
  fi

fi

# if not yet defined, use the same certificate for alt
[ -z "$NOMAD_ALT_CERTIFICATE_NAME_VARIABLE" ] && NOMAD_ALT_CERTIFICATE_NAME_VARIABLE="${NOMAD_CERTIFICATE_NAME_VARIABLE}"
[ -z "$NOMAD_ALT_CA_CERTIFICATE_VARIABLE" ] && NOMAD_ALT_CA_CERTIFICATE_VARIABLE="${NOMAD_CA_CERTIFICATE_VARIABLE}"
[ -z "$NOMAD_ALT_PUBLIC_CERTIFICATE_VARIABLE" ] && NOMAD_ALT_PUBLIC_CERTIFICATE_VARIABLE="${NOMAD_PUBLIC_CERTIFICATE_VARIABLE}"
[ -z "$NOMAD_ALT_PRIVATE_KEY_VARIABLE" ] && NOMAD_ALT_PRIVATE_KEY_VARIABLE="${NOMAD_PRIVATE_KEY_VARIABLE}"

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

[ -z "$POSTINSTALL_STATUS_FILE" ] && POSTINSTALL_STATUS_FILE="$(realpath $LOCAL_PATH/../../..)/test-results/nomad_postinstall_status.txt"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/nomad-pool/$POOL_TYPE/terraform.tfstate"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$NOMAD_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="NobleBase"

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

# ensure no output for ansible vault contents
set +x
set -e
set -o pipefail
CA_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_CA_CERTIFICATE_VARIABLE}" -)
PUBLIC_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_PUBLIC_CERTIFICATE_VARIABLE}" -)
PRIVATE_KEY=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_PRIVATE_KEY_VARIABLE}" -)
ALT_CA_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_ALT_CA_CERTIFICATE_VARIABLE}" -)
ALT_PUBLIC_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_ALT_PUBLIC_CERTIFICATE_VARIABLE}" -)
ALT_PRIVATE_KEY=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_ALT_PRIVATE_KEY_VARIABLE}" -)
NOMAD_CERTIFICATE_NAME=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_CERTIFICATE_NAME_VARIABLE}" -)
NOMAD_ALT_CERTIFICATE_NAME=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${NOMAD_ALT_CERTIFICATE_NAME_VARIABLE}" -)
set +e
set +o pipefail

[[ "$NOMAD_ALT_CERTIFICATE_NAME" == "$NOMAD_CERTIFICATE_NAME" ]] && NOMAD_ALT_CERTIFICATE_NAME="${NOMAD_ALT_CERTIFICATE_NAME}-alt"

# export private key to variable instead of outputting on command line
export TF_VAR_certificate_public_certificate="$PUBLIC_CERTIFICATE"
export TF_VAR_certificate_private_key="$PRIVATE_KEY"
export TF_VAR_certificate_ca_certificate="$CA_CERTIFICATE"
export TF_VAR_alt_certificate_public_certificate="$ALT_PUBLIC_CERTIFICATE"
export TF_VAR_alt_certificate_private_key="$ALT_PRIVATE_KEY"
export TF_VAR_alt_certificate_ca_certificate="$ALT_CA_CERTIFICATE"
set -x


[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"
[ -z "$PRIVATE_DNS_NAME" ] && PRIVATE_DNS_NAME="$RESOURCE_NAME_ROOT-internal.$DNS_ZONE_NAME"

[ -z "$NOMAD_LB_HOSTNAMES" ] && NOMAD_LB_HOSTNAMES="[\"$RESOURCE_NAME_ROOT.$TOP_LEVEL_DNS_ZONE_NAME\",\"${ENVIRONMENT}-${ORACLE_REGION}-jigasi-selector.$TOP_LEVEL_DNS_ZONE_NAME\",\"${ENVIRONMENT}-${ORACLE_REGION}-autoscaler.$TOP_LEVEL_DNS_ZONE_NAME\",\"${ENVIRONMENT}-${ORACLE_REGION}-api.$TOP_LEVEL_DNS_ZONE_NAME\",\"${ENVIRONMENT}-api.$TOP_LEVEL_DNS_ZONE_NAME\"]"
[ -z "$NOMAD_ALT_HOSTNAMES" ] && NOMAD_ALT_HOSTNAMES="[\"$DOMAIN\"]"

# if environment has skynet alt hostname, add it to the list
if [ -n "$SKYNET_ALT_HOSTNAME" ]; then
  NOMAD_LB_HOSTNAMES="$(echo "$NOMAD_LB_HOSTNAMES" "[\"$SKYNET_ALT_HOSTNAME\"]" | jq -c -s '.|add' )"
fi

[ -n "$NOMAD_LB_EXTRA_HOSTNAMES" ] && NOMAD_LB_HOSTNAMES="$(echo "$NOMAD_LB_HOSTNAMES" "$NOMAD_LB_EXTRA_HOSTNAMES" | jq -c -s '.|add' )"

[ -n "$NOMAD_ALT_EXTRA_HOSTNAMES" ] && NOMAD_ALT_HOSTNAMES="$(echo "$NOMAD_ALT_HOSTNAMES" "$NOMAD_ALT_EXTRA_HOSTNAMES" | jq -c -s '.|add' )"

[ -z "$LOAD_BALANCER_SHAPE" ] && LOAD_BALANCER_SHAPE="flexible"
[ -z "$NOMAD_LOAD_BALANCER_MAXIMUM_BANDWIDTH_IN_MBPS" ] && NOMAD_LOAD_BALANCER_MAXIMUM_BANDWIDTH_IN_MBPS=100

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
TF_GLOBALS_CHDIR_SG=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_GLOBALS_CHDIR_SG="-chdir=$LOCAL_PATH/security-group"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
  TF_POST_PARAMS_SG=
else
  TF_POST_PARAMS="$LOCAL_PATH"
  TF_POST_PARAMS_SG="$LOCAL_PATH/security-group"
fi

# first find or create the nomad security group
[ -z "$S3_STATE_KEY_NOMAD_SG" ] && S3_STATE_KEY_NOMAD_SG="$ENVIRONMENT/nomad-pool/$POOL_TYPE/terraform-nomad-sg.tfstate"
LOCAL_NOMAD_SG_KEY="terraform-nomad-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_NOMAD_SG --region $ORACLE_REGION --file $LOCAL_NOMAD_SG_KEY

if [ $? -eq 0 ]; then
  NOMAD_SECURITY_GROUP_ID="$(cat $LOCAL_NOMAD_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ "$UPDATE_SECURITY_GROUP" == "true" ]; then
  NOMAD_SECURITY_GROUP_ID=
fi

if [ -z "$NOMAD_SECURITY_GROUP_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_SG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_NOMAD_SG" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS_SG

  terraform $TF_GLOBALS_CHDIR_SG apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -var="compartment_ocid=$COMPARTMENT_OCID" \
    -var="vcn_name=$VCN_NAME" \
    -var="resource_name_root=$RESOURCE_NAME_ROOT" \
    -var="ephemeral_ingress_cidr=$EPHEMERAL_INGRESS_CIDR" \
    -auto-approve $TF_POST_PARAMS_SG

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_NOMAD_SG --region $ORACLE_REGION --file $LOCAL_NOMAD_SG_KEY

  NOMAD_SECURITY_GROUP_ID="$(cat $LOCAL_NOMAD_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"

fi

if [ -z "$NOMAD_SECURITY_GROUP_ID" ]; then
  echo "NOMAD_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 2
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
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="pool_type=$POOL_TYPE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="public_subnet_ocid=$PUBLIC_SUBNET_OCID" \
  -var="pool_subnet_ocid=$POOL_SUBNET_OCID" \
  -var="instance_pool_size=$INSTANCE_POOL_SIZE" \
  -var="instance_pool_name=$INSTANCE_POOL_NAME" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user=$SSH_USER" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="security_group_id=$NOMAD_SECURITY_GROUP_ID" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="shape=$SHAPE" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="ocpus=$OCPUS" \
  -var="disk_in_gbs=$DISK_IN_GBS" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
  -var="vcn_name=$VCN_NAME" \
  -var="load_balancer_shape=$LOAD_BALANCER_SHAPE" \
  -var="load_balancer_shape_details_maximum_bandwidth_in_mbps=$NOMAD_LOAD_BALANCER_MAXIMUM_BANDWIDTH_IN_MBPS" \
  -var="dns_name=$DNS_NAME" \
  -var="private_dns_name=$PRIVATE_DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="lb_hostnames=$NOMAD_LB_HOSTNAMES"\
  -var="alt_hostnames=$NOMAD_ALT_HOSTNAMES"\
  -var="certificate_certificate_name=$NOMAD_CERTIFICATE_NAME" \
  -var="alt_certificate_certificate_name=$NOMAD_ALT_CERTIFICATE_NAME" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
