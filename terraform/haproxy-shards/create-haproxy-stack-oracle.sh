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

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -z "$ROLE" ] && ROLE="haproxy"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"
[ -z "$HAPROXY_RELEASE_NUMBER" ] && HAPROXY_RELEASE_NUMBER="0"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_HAPROXY_SHAPE"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"
[ -z "$OCPUS" ] && OCPUS="2"

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=2

[ -z "$NAME_ROOT" ] && NAME_ROOT="$NAME"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${NAME_ROOT}-InstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-InstanceConfig"

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

# assume regional hostnames will be appended like tokyo-stage.8x8.vc
[ -z "$REGION_HOSTNAME_SEPARATOR" ] && REGION_HOSTNAME_SEPARATOR="-"

[ -z "$LB_HOSTNAMES" ] && LB_HOSTNAMES="$DOMAIN"
if [[ "$HAPROXY_REGIONAL_HOSTNAMES" == "true" ]]; then
  if [ ! -z "$REGION_HOSTNAME" ]; then
    LB_HOSTNAMES="$LB_HOSTNAMES ${REGION_HOSTNAME}${REGION_HOSTNAME_SEPARATOR}${DOMAIN}"
  fi
  LB_HOSTNAMES="$LB_HOSTNAMES test${REGION_HOSTNAME_SEPARATOR}${DOMAIN}"
fi
LB_HOSTNAME_JSON="[]"
for LB_HOSTNAME in $LB_HOSTNAMES; do
  LB_HOSTNAME_JSON=$(echo $LB_HOSTNAME_JSON "[\"$LB_HOSTNAME\"]" | jq -c --slurp 'flatten(1)')
done

[ -z "$CERTIFICATE_NAME" ] && CERTIFICATE_NAME="star_jitsi_net-2024-08-10"
[ -z "$CA_CERTIFICATE_VARIABLE" ] && CA_CERTIFICATE_VARIABLE="jitsi_net_ssl_extras"
[ -z "$PUBLIC_CERTIFICATE_VARIABLE" ] && PUBLIC_CERTIFICATE_VARIABLE="jitsi_net_ssl_certificate"
[ -z "$PRIVATE_KEY_VARIABLE" ] && PRIVATE_KEY_VARIABLE="jitsi_net_ssl_key_name"

[ -z "$SIGNAL_API_HOSTNAME" ] && SIGNAL_API_HOSTNAME="signal-api-$ENVIRONMENT.jitsi.net"
[ -z "$SIGNAL_API_CERTIFICATE_NAME" ] && SIGNAL_API_CERTIFICATE_NAME="star_jitsi_net-2024-08-10"
[ -z "$SIGNAL_API_CA_CERTIFICATE_VARIABLE" ] && SIGNAL_API_CA_CERTIFICATE_VARIABLE="jitsi_net_ssl_extras"
[ -z "$SIGNAL_API_PUBLIC_CERTIFICATE_VARIABLE" ] && SIGNAL_API_PUBLIC_CERTIFICATE_VARIABLE="jitsi_net_ssl_certificate"
[ -z "$SIGNAL_API_PRIVATE_KEY_VARIABLE" ] && SIGNAL_API_PRIVATE_KEY_VARIABLE="jitsi_net_ssl_key_name"

[ -z "$ALARM_PAGERDUTY_TOPIC_NAME" ] && ALARM_PAGERDUTY_TOPIC_NAME="${ENVIRONMENT}-PagerDutyTopic"
[ -z "$ALARM_EMAIL_TOPIC_NAME" ] && ALARM_EMAIL_TOPIC_NAME="${ENVIRONMENT}-topic"

[ -z "$ENABLE_PAGERDUTY_ALARMS" ] && ENABLE_PAGERDUTY_ALARMS="false"
[ -z "$ALARM_PAGERDUTY_ENABLED" ] && ALARM_PAGERDUTY_ENABLED="$ENABLE_PAGERDUTY_ALARMS"

# leave alarms disabled until stack is fully up
[ -z "$ALARM_INITIAL_ENABLED" ] && ALARM_INITIAL_ENABLED="false"

if [[ "$ALARM_INITIAL_ENABLED" == "false" ]]; then
  ALARM_PAGERDUTY_ENABLED="false"
fi

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
CA_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${CA_CERTIFICATE_VARIABLE}" -)
PUBLIC_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${PUBLIC_CERTIFICATE_VARIABLE}" -)
PRIVATE_KEY=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${PRIVATE_KEY_VARIABLE}" -)

# export private key to variable instead of outputting on command line
export TF_VAR_certificate_public_certificate="$PUBLIC_CERTIFICATE"
export TF_VAR_certificate_private_key="$PRIVATE_KEY"
export TF_VAR_certificate_ca_certificate="$CA_CERTIFICATE"

if [[ "$SIGNAL_API_CERTIFICATE_NAME" == "$CERTIFICATE_NAME" ]]; then
  # shared cert, so give the signal api one a differnt name
  SIGNAL_API_CERTIFICATE_NAME="$SIGNAL_API_CERTIFICATE_NAME-signal"
else
  CA_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIGNAL_API_CA_CERTIFICATE_VARIABLE}" -)
  PUBLIC_CERTIFICATE=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIGNAL_API_PUBLIC_CERTIFICATE_VARIABLE}" -)
  PRIVATE_KEY=$(ansible-vault view $ENCRYPTED_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIGNAL_API_PRIVATE_KEY_VARIABLE}" -)
fi
set +e
set +o pipefail

# export signal API private key to variable instead of outputting on command line
export TF_VAR_signal_api_certificate_public_certificate="$PUBLIC_CERTIFICATE"
export TF_VAR_signal_api_certificate_private_key="$PRIVATE_KEY"
export TF_VAR_signal_api_certificate_ca_certificate="$CA_CERTIFICATE"

set -x

RESOURCE_NAME_ROOT="${NAME_ROOT}"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"

[ -z "$LOAD_BALANCER_SHAPE" ] && LOAD_BALANCER_SHAPE="flexible"

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

[ -z "$POSTINSTALL_STATUS_FILE" ] && POSTINSTALL_STATUS_FILE="$LOCAL_PATH/../../../test-results/haproxy_postinstall_status.txt"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/haproxy-components/terraform.tfstate"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$HAPROXY_BASE_IMAGE_TYPE"
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
TF_GLOBALS_CHDIR_SG=
TF_GLOBALS_CHDIR_LBSG=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_GLOBALS_CHDIR_SG="-chdir=$LOCAL_PATH/security-group"
  TF_GLOBALS_CHDIR_LBSG="-chdir=$LOCAL_PATH/load-balancer-security-group"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
  TF_POST_PARAMS_SG=
  TF_POST_PARAMS_LBSG=
else
  TF_POST_PARAMS="$LOCAL_PATH"
  TF_POST_PARAMS_SG="$LOCAL_PATH/security-group"
  TF_POST_PARAMS_LBSG="$LOCAL_PATH/load-balancer-security-group"
fi

# first find or create the haproxy security group
[ -z "$S3_STATE_KEY_HAPROXY_SG" ] && S3_STATE_KEY_HAPROXY_SG="$ENVIRONMENT/haproxy-components/terraform-haproxy-sg.tfstate"
LOCAL_HAPROXY_SG_KEY="terraform-haproxy-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_HAPROXY_SG --region $ORACLE_REGION --file $LOCAL_HAPROXY_SG_KEY

if [ $? -eq 0 ]; then
  HAPROXY_SECURITY_GROUP_ID="$(cat $LOCAL_HAPROXY_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$HAPROXY_SECURITY_GROUP_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_SG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_HAPROXY_SG" \
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
    -auto-approve $TF_POST_PARAMS_SG

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_HAPROXY_SG --region $ORACLE_REGION --file $LOCAL_HAPROXY_SG_KEY

  HAPROXY_SECURITY_GROUP_ID="$(cat $LOCAL_HAPROXY_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"

fi

if [ -z "$HAPROXY_SECURITY_GROUP_ID" ]; then
  echo "HAPROXY_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 2
fi

# first find or create the load balancer security group
[ -z "$S3_STATE_LB_KEY_SG" ] && S3_STATE_LB_KEY_SG="$ENVIRONMENT/haproxy-components/terraform-lb-sg.tfstate"
LOCAL_LB_KEY_SG="terraform-lb-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_LB_KEY_SG --region $ORACLE_REGION --file $LOCAL_LB_KEY_SG

if [ $? -eq 0 ]; then
  LB_SECURITY_GROUP_ID="$(cat $LOCAL_LB_KEY_SG | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$LB_SECURITY_GROUP_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_LBSG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_LB_KEY_SG" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS_LBSG

  terraform $TF_GLOBALS_CHDIR_LBSG apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -var="compartment_ocid=$COMPARTMENT_OCID" \
    -var="vcn_name=$VCN_NAME" \
    -var="resource_name_root=$ENVIRONMENT-$ORACLE_REGION-haproxy-lb" \
    -auto-approve $TF_POST_PARAMS_LBSG

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_LB_KEY_SG --region $ORACLE_REGION --file $LOCAL_LB_KEY_SG

  LB_SECURITY_GROUP_ID="$(cat $LOCAL_LB_KEY_SG | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"

fi

if [ -z "$LB_SECURITY_GROUP_ID" ]; then
  echo "LB_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 3
fi

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

# The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure $TF_POST_PARAMS

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="environment=$ENVIRONMENT" \
  -var="name=$NAME" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="git_branch=$ORACLE_GIT_BRANCH" \
  -var="haproxy_release_number=$HAPROXY_RELEASE_NUMBER" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="resource_name_root=$RESOURCE_NAME_ROOT" \
  -var="load_balancer_shape=$LOAD_BALANCER_SHAPE" \
  -var="public_subnet_ocid=$PUBLIC_SUBNET_OCID" \
  -var="private_subnet_ocid=$NAT_SUBNET_OCID" \
  -var="instance_pool_size=$INSTANCE_POOL_SIZE" \
  -var="instance_pool_name=$INSTANCE_POOL_NAME" \
  -var="dns_name=$DNS_NAME" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  -var="dns_compartment_ocid=$TENANCY_OCID" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="user=$SSH_USER" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="security_group_id=$HAPROXY_SECURITY_GROUP_ID" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="shape=$SHAPE" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="ocpus=$OCPUS" \
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  -var="alarm_pagerduty_is_enabled=$ALARM_PAGERDUTY_ENABLED" \
  -var="alarm_pagerduty_topic_name=$ALARM_PAGERDUTY_TOPIC_NAME" \
  -var="alarm_email_topic_name=$ALARM_EMAIL_TOPIC_NAME" \
  -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
  -var="lb_security_group_id=$LB_SECURITY_GROUP_ID" \
  -var="certificate_certificate_name=$CERTIFICATE_NAME" \
  -var="lb_hostnames=$LB_HOSTNAME_JSON" \
  -var="signal_api_hostname=$SIGNAL_API_HOSTNAME" \
  -var="signal_api_certificate_certificate_name=$SIGNAL_API_CERTIFICATE_NAME" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS