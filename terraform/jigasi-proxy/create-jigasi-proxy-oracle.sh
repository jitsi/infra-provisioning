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

[ -z "$ROLE" ] && ROLE="jigasi-proxy"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$DEFAULT_JIGASI_PROXY_SHAPE"

[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"
[ -z "$OCPUS" ] && OCPUS="1"

[ -z "$INSTANCE_POOL_SIZE" ] && INSTANCE_POOL_SIZE=2

[ -z "$NAME_ROOT_SUFFIX" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION"
[ -z "$NAME_ROOT" ] && NAME_ROOT="$ENVIRONMENT-$ORACLE_REGION-$NAME_ROOT_SUFFIX"

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="${NAME_ROOT}-JigasiProxyInstancePool"
[ -z "$INSTANCE_CONFIG_NAME" ] && INSTANCE_CONFIG_NAME="${NAME_ROOT}-JigasiProxyInstanceConfig"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

RESOURCE_NAME_ROOT="${NAME_ROOT}-jigasi-proxy"

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

[ -z "$JIGASI_PROXY_POSTINSTALL_STATUS_FILE" ] && JIGASI_PROXY_POSTINSTALL_STATUS_FILE="/tmp/jigasi_proxy_postinstall_status.txt"

if [ "$SKIP_SSH_BASTION_HOST" == "true" ]; then
  BASTION_CONFIG=""
else
  [ -z "$BASTION_HOST" ] && BASTION_HOST="$CONNECTION_SSH_BASTION_HOST"

  # add bastion hosts to known hosts if not present
  grep -q "$BASTION_HOST" ~/.ssh/known_hosts || ssh-keyscan -H $BASTION_HOST >> ~/.ssh/known_hosts

  BASTION_CONFIG='-var="bastion_host=$BASTION_HOST"'
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/jigasi-proxy-components/terraform.tfstate"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$JIGASI_PROXY_BASE_IMAGE_TYPE"
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
  TF_GLOBALS_CHDIR_SG="-chdir=$LOCAL_PATH/jigasi-proxy-security-group"
  TF_GLOBALS_CHDIR_LBSG="-chdir=$LOCAL_PATH/jigasi-load-balancer-security-group"
  
  TF_POST_PARAMS=
  TF_POST_PARAMS_SG=
  TF_POST_PARAMS_LBSG=
else
  TF_POST_PARAMS="$LOCAL_PATH"
  TF_POST_PARAMS_SG="$LOCAL_PATH/jigasi-proxy-security-group"
  TF_POST_PARAMS_LBSG="$LOCAL_PATH/jigasi-load-balancer-security-group"
fi


# first find or create the jigasi proxy security group
[ -z "$S3_STATE_KEY_JIGASI_PROXY_SG" ] && S3_STATE_KEY_JIGASI_PROXY_SG="$ENVIRONMENT/jigasi-proxy-components/terraform-jigasi-proxy-sg.tfstate"
LOCAL_JIGASI_PROXY_SG_KEY="terraform-jigasi-proxy-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_JIGASI_PROXY_SG --region $ORACLE_REGION --file $LOCAL_JIGASI_PROXY_SG_KEY

if [ $? -eq 0 ]; then
  JIGASI_PROXY_SECURITY_GROUP_ID="$(cat $LOCAL_JIGASI_PROXY_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$JIGASI_PROXY_SECURITY_GROUP_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_SG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_JIGASI_PROXY_SG" \
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

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_JIGASI_PROXY_SG --region $ORACLE_REGION --file $LOCAL_JIGASI_PROXY_SG_KEY

  JIGASI_PROXY_SECURITY_GROUP_ID="$(cat $LOCAL_JIGASI_PROXY_SG_KEY | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"

fi

if [ -z "$JIGASI_PROXY_SECURITY_GROUP_ID" ]; then
  echo "JIGASI_PROXY_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 2
fi

# first find or create the jigasi load balancer security group
[ -z "$S3_STATE_JIGASI_LB_KEY_SG" ] && S3_STATE_JIGASI_LB_KEY_SG="$ENVIRONMENT/jigasi-proxy-components/terraform-jigasi-lb-sg.tfstate"
LOCAL_JIGASI_LB_KEY_SG="terraform-jigasi-lb-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_JIGASI_LB_KEY_SG --region $ORACLE_REGION --file $LOCAL_JIGASI_LB_KEY_SG

if [ $? -eq 0 ]; then
  JIGASI_LB_SECURITY_GROUP_ID="$(cat $LOCAL_JIGASI_LB_KEY_SG | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$JIGASI_LB_SECURITY_GROUP_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_LBSG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_JIGASI_LB_KEY_SG" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS_LBSG

  terraform $TF_GLOBALS_CHDIR_LBSG apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -var="compartment_ocid=$COMPARTMENT_OCID" \
    -var="vcn_name=$VCN_NAME" \
    -var="resource_name_root=$ENVIRONMENT-$ORACLE_REGION-jigasi-lb" \
    -auto-approve $TF_POST_PARAMS_LBSG

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_JIGASI_LB_KEY_SG --region $ORACLE_REGION --file $LOCAL_JIGASI_LB_KEY_SG

  JIGASI_LB_SECURITY_GROUP_ID="$(cat $LOCAL_JIGASI_LB_KEY_SG | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"

fi

if [ -z "$JIGASI_LB_SECURITY_GROUP_ID" ]; then
  echo "JIGASI_LB_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 3
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
  -var="git_branch=$ORACLE_GIT_BRANCH" \
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
  -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
  $BASTION_CONFIG \
  -var="jigasi_proxy_postinstall_status_file=$JIGASI_PROXY_POSTINSTALL_STATUS_FILE" \
  -var="image_ocid=$IMAGE_OCID" \
  -var="instance_config_name=$INSTANCE_CONFIG_NAME" \
  -var="security_group_id=$JIGASI_PROXY_SECURITY_GROUP_ID" \
  -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
  -var="shape=$SHAPE" \
  -var="memory_in_gbs=$MEMORY_IN_GBS" \
  -var="ocpus=$OCPUS" \
  -var="lb_security_group_id=$JIGASI_LB_SECURITY_GROUP_ID" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
