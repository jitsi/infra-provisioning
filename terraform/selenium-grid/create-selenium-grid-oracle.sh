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

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z $GRID_NAME ]; then
  echo "No GRID_NAME provided or found. Exiting..."
  exit 202
fi

if [ -z $ORACLE_REGION ]; then
  echo "No ORACLE_REGION provided or found. Exiting..."
  exit 203
fi

[ -z "$ROLE" ] && ROLE="selenium-grid"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$GRID_NAME"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh


if [ -z "$INFRA_CONFIGURATION_REPO" ]; then
  echo "No INFRA_CONFIGURATION_REPO found. using default..."
  export INFRA_CONFIGURATION_REPO="https://github.com/jitsi/infra-configuration.git"
fi

[ -z "$INFRA_CUSTOMIZATIONS_REPO" ] && INFRA_CUSTOMIZATIONS_REPO="$PRIVATE_CUSTOMIZATIONS_REPO"

if [ -z "$INFRA_CUSTOMIZATIONS_REPO" ]; then
  echo "No INFRA_CUSTOMIZATIONS_REPO found. Exiting..."
  exit 203
fi


[ -z "$SHAPE_X86" ] && SHAPE_X86="$SHAPE_E_6"
[ -z "$SHAPE_X86" ] && SHAPE_X86="VM.Standard.E6.Flex"
[ -z "$SHAPE_ARM" ] && SHAPE_ARM="$SHAPE_A_1"
[ -z "$SHAPE_ARM" ] && SHAPE_ARM="VM.Standard.A1.Flex"

[ -z "$MEMORY_IN_GBS_X86" ] && MEMORY_IN_GBS_X86="8"
[ -z "$OCPUS_X86" ] && OCPUS_X86="2"

[ -z "$MEMORY_IN_GBS_ARM" ] && MEMORY_IN_GBS_ARM="8"
[ -z "$OCPUS_ARM" ] && OCPUS_ARM="4"

[ -z "$INSTANCE_POOL_SIZE_X86" ] && INSTANCE_POOL_SIZE_X86=1
[ -z "$INSTANCE_POOL_SIZE_ARM" ] && INSTANCE_POOL_SIZE_ARM=1

[ -z "$INSTANCE_POOL_NAME" ] && INSTANCE_POOL_NAME="GridInstancePool"

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

[ -z "$UPGRADE_GRID" ] && UPGRADE_GRID="false"

RESOURCE_NAME_ROOT="$NAME"

[ -z "$DNS_NAME" ] && DNS_NAME="$RESOURCE_NAME_ROOT.$DNS_ZONE_NAME"

[ -z "$LOAD_BALANCER_SHAPE" ] && LOAD_BALANCER_SHAPE="100Mbps"

[ -z "$SELENIUM_GRID_NOMAD_ENABLED" ] && SELENIUM_GRID_NOMAD_ENABLED="$SELENIUM_GRID_NOMAD_FLAG"
[ -z "$SELENIUM_GRID_NOMAD_ENABLED" ] && SELENIUM_GRID_NOMAD_ENABLED="false"

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

S3_STATE_BASE="$ENVIRONMENT/grid/$GRID_NAME/components"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"

if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
  IMAGE_TYPE="NobleBase"
else
  IMAGE_TYPE="SeleniumGrid"
fi

arch_from_shape $SHAPE_X86

[ -z "$IMAGE_OCID_X86" ] && IMAGE_OCID_X86=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type $IMAGE_TYPE --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID_X86" ]; then
  echo "No IMAGE_OCID_X86 found.  Exiting..."
  exit 210
fi

arch_from_shape $SHAPE_ARM

[ -z "$IMAGE_OCID_ARM" ] && IMAGE_OCID_ARM=$($LOCAL_PATH/../../scripts/oracle_custom_images.py --type $IMAGE_TYPE --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ -z "$IMAGE_OCID_ARM" ]; then
  echo "No IMAGE_OCID_ARM found.  Exiting..."
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
TF_GLOBALS_CHDIR_LB=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
    TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH//instance-pool-nomad"
  else
    TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH//instance-pool"
  fi
  TF_GLOBALS_CHDIR_SG="-chdir=$LOCAL_PATH/security-group"
  TF_GLOBALS_CHDIR_LB="-chdir=$LOCAL_PATH/load-balancer"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
  TF_POST_PARAMS_SG=
  TF_POST_PARAMS_LB=
else
  if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
    TF_POST_PARAMS="$LOCAL_PATH//instance-pool-nomad"
  else
    TF_POST_PARAMS="$LOCAL_PATH//instance-pool"
  fi
  TF_POST_PARAMS_SG="$LOCAL_PATH/security-group"
  TF_POST_PARAMS_LB="$LOCAL_PATH/load-balancer"
fi

# first find or create the security group
[ -z "$S3_STATE_KEY_SG" ] && S3_STATE_KEY_SG="${S3_STATE_BASE}/terraform-sg.tfstate"
LOCAL_SG_KEY="terraform-sg.tfstate"
RUN_TF=false
oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_SG --region $ORACLE_REGION --file $LOCAL_SG_KEY
if [ $? -eq 0 ]; then
  # immediately use existing IDs
  RESOURCES=$(cat $LOCAL_SG_KEY | jq -r '.resources|length')
  if [[ "$RESOURCES" -eq 0 ]]; then
    RUN_TF=true
  else
    if [[ "$UPGRADE_GRID" == "true" ]]; then
      echo "UPGRADE_GRID set, updating security groups"
      RUN_TF=true
    else
      echo "Using existing security group IDs found in bucket state file"
    fi
  fi
else
    RUN_TF=true
fi
if $RUN_TF; then
  terraform $TF_GLOBALS_CHDIR_SG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_SG" \
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

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_SG --region $ORACLE_REGION --file $LOCAL_SG_KEY
  if [ $? -eq 0 ]; then
    echo "Using new bucket state file generated from terraform apply"
  else
    echo "Failure fetching newly applied terraform state, security groups may not be defined properly below"
  fi

fi

HUB_SECURITY_GROUP_ID="$(cat $LOCAL_SG_KEY | jq -r '.resources[]
    | select(.type == "oci_core_network_security_group")
    | .instances[]
    | select(.attributes.display_name == "'$RESOURCE_NAME_ROOT'-HubSecurityGroup")
    | .attributes.id')"  

NODE_SECURITY_GROUP_ID="$(cat $LOCAL_SG_KEY | jq -r '.resources[]
    | select(.type == "oci_core_network_security_group")
    | .instances[]
    | select(.attributes.display_name == "'$RESOURCE_NAME_ROOT'-NodeSecurityGroup")
    | .attributes.id')"  

if [ -z "$HUB_SECURITY_GROUP_ID" ]; then
  echo "HUB_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 2
fi
if [ -z "$NODE_SECURITY_GROUP_ID" ]; then
  echo "NODE_SECURITY_GROUP_ID failed to be found or created, exiting..."
  exit 2
fi

if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
  echo "Skipping load balancer for nomad selenium grid"
else
  # next step is the load balancer and associated backend set
  # 35.163.97.98 - ci.jitsi.org
  # 52.41.182.55 - jenkins.jitsi.net
  # 129.146.35.175 - jenkins-ops.jitsi.net
  # 129.146.91.164 - alpha.jitsi.net
  [ -z "$LB_WHITELIST" ] && LB_WHITELIST='["10.0.0.0/8","35.163.97.98/32","52.41.182.55/32","129.146.35.175/32","129.146.91.164/32"]'

  [ -z "$S3_STATE_KEY_LB" ] && S3_STATE_KEY_LB="${S3_STATE_BASE}/terraform-lb.tfstate"

  LOCAL_LB_KEY="terraform-lb.tfstate"
  RUN_TF=false
  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_LB --region $ORACLE_REGION --file $LOCAL_LB_KEY
  if [ $? -eq 0 ]; then
    RESOURCES=$(cat $LOCAL_LB_KEY | jq -r '.resources|length')
    if [[ "$RESOURCES" -eq 0 ]]; then
      RUN_TF=true
    else
      if [[ "$UPGRADE_GRID" == "true" ]]; then
        echo "UPGRADE_GRID set, updating load balancer"
        RUN_TF=true
      else
        echo "Using existing tfstate file for load balancer"
      fi
    fi
  else
      RUN_TF=true
  fi
  if $RUN_TF; then
    terraform $TF_GLOBALS_CHDIR_LB init \
      -backend-config="bucket=$S3_STATE_BUCKET" \
      -backend-config="key=$S3_STATE_KEY_LB" \
      -backend-config="region=$ORACLE_REGION" \
      -backend-config="profile=$S3_PROFILE" \
      -backend-config="endpoint=$S3_ENDPOINT" \
      -reconfigure $TF_POST_PARAMS_LB

    terraform $TF_GLOBALS_CHDIR_LB apply \
      -var="vcn_name=$VCN_NAME" \
      -var="load_balancer_shape=$LOAD_BALANCER_SHAPE" \
      -var="resource_name_root=$RESOURCE_NAME_ROOT" \
      -var="oracle_region=$ORACLE_REGION" \
      -var="tenancy_ocid=$TENANCY_OCID" \
      -var="compartment_ocid=$COMPARTMENT_OCID" \
      -var="subnet_ocid=$PUBLIC_SUBNET_OCID" \
      -var="dns_zone_name=$DNS_ZONE_NAME" \
      -var="dns_name=$DNS_NAME" \
      -var="dns_compartment_ocid=$TENANCH_OCID" \
      -var="whitelist=$LB_WHITELIST" \
      -var="role=$ROLE" \
      -var="grid_name=$GRID_NAME" \
      -var="environment=$ENVIRONMENT" \
      -var="tag_namespace=$TAG_NAMESPACE" \
      -auto-approve $TF_POST_PARAMS_LB

    oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_LB --region $ORACLE_REGION --file $LOCAL_LB_KEY
    if [ $? -eq 0 ]; then
      echo "Using new load balancer bucket state file generated from terraform apply"
    else
      echo "Failure fetching newly applied terraform state, load balancers may not be defined properly below"
    fi
  fi

  LOAD_BALANCER_ID="$(cat $LOCAL_LB_KEY | jq -r '.resources[]
      | select(.type == "oci_load_balancer")
      | .instances[]
      | select(.attributes.display_name == "'$RESOURCE_NAME_ROOT'-LoadBalancer")
      | .attributes.id')"
  BACKEND_SET_NAME="$(cat $LOCAL_LB_KEY | jq -r '.resources[]
      | select(.type == "oci_load_balancer_backend_set")
      | .instances[]
      | .attributes.name')"

  if [ -z "$LOAD_BALANCER_ID" ]; then
    echo "LOAD_BALANCER_ID failed to be found or created, exiting..."
    exit 3
  fi
  if [ -z "$BACKEND_SET_NAME" ]; then
    echo "BACKEND_SET_NAME failed to be found or created, exiting..."
    exit 4
  fi

fi


[ -z "$S3_STATE_KEY_IP" ] && S3_STATE_KEY_IP="${S3_STATE_BASE}/terraform-ip.tfstate"

LOCAL_IP_KEY="terraform-ip.tfstate"
RUN_TF=false
oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_IP --region $ORACLE_REGION --file $LOCAL_IP_KEY
if [ $? -eq 0 ]; then
  RESOURCES=$(cat $LOCAL_IP_KEY | jq -r '.resources|length')
  if [[ "$RESOURCES" -eq 0 ]]; then
    RUN_TF=true
  else
    if [[ "$UPGRADE_GRID" == "true" ]]; then
      echo "UPGRADE_GRID set, updating instance pool"
      RUN_TF=true
    else
      echo "Using existing tfstate file for instance pools"
    fi
  fi
else
    RUN_TF=true
fi
if $RUN_TF; then
  terraform $TF_GLOBALS_CHDIR init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_IP" \
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

  if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
    terraform $TF_GLOBALS_CHDIR $ACTION \
        -var="environment=$ENVIRONMENT" \
        -var="name=$NAME" \
        -var="oracle_region=$ORACLE_REGION" \
        -var="availability_domains=$AVAILABILITY_DOMAINS" \
        -var="vcn_name=$VCN_NAME" \
        -var="role=$ROLE" \
        -var="grid_name=$GRID_NAME" \
        -var="git_branch=$ORACLE_GIT_BRANCH" \
        -var="tenancy_ocid=$TENANCY_OCID" \
        -var="compartment_ocid=$COMPARTMENT_OCID" \
        -var="resource_name_root=$RESOURCE_NAME_ROOT" \
        -var="subnet_ocid=$NAT_SUBNET_OCID" \
        -var="instance_pool_size_x86=$INSTANCE_POOL_SIZE_X86" \
        -var="instance_pool_size_arm=$INSTANCE_POOL_SIZE_ARM" \
        -var="shape_x86=$SHAPE_X86" \
        -var="shape_arm=$SHAPE_ARM" \
        -var="image_ocid_x86=$IMAGE_OCID_X86" \
        -var="image_ocid_arm=$IMAGE_OCID_ARM" \
        -var="node_security_group_id=$NODE_SECURITY_GROUP_ID" \
        -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
        -var="memory_in_gbs_x86=$MEMORY_IN_GBS_X86" \
        -var="memory_in_gbs_arm=$MEMORY_IN_GBS_ARM" \
        -var="ocpus_x86=$OCPUS_X86" \
        -var="ocpus_arm=$OCPUS_ARM" \
        -var="environment_type=$ENVIRONMENT_TYPE" \
        -var="tag_namespace=$TAG_NAMESPACE" \
        -var="jitsi_tag_namespace=$JITSI_TAG_NAMESPACE" \
        -var="user=$SSH_USER" \
        -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
        -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
        -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
        -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
        $ACTION_POST_PARAMS $TF_POST_PARAMS
  else
    terraform $TF_GLOBALS_CHDIR $ACTION \
        -var="environment=$ENVIRONMENT" \
        -var="name=$NAME" \
        -var="oracle_region=$ORACLE_REGION" \
        -var="availability_domains=$AVAILABILITY_DOMAINS" \
        -var="vcn_name=$VCN_NAME" \
        -var="role=$ROLE" \
        -var="grid_name=$GRID_NAME" \
        -var="git_branch=$ORACLE_GIT_BRANCH" \
        -var="tenancy_ocid=$TENANCY_OCID" \
        -var="compartment_ocid=$COMPARTMENT_OCID" \
        -var="resource_name_root=$RESOURCE_NAME_ROOT" \
        -var="subnet_ocid=$NAT_SUBNET_OCID" \
        -var="instance_pool_size=$INSTANCE_POOL_SIZE_X86" \
        -var="shape=$SHAPE_X86" \
        -var="image_ocid=$IMAGE_OCID_X86" \
        -var="hub_security_group_id=$HUB_SECURITY_GROUP_ID" \
        -var="node_security_group_id=$NODE_SECURITY_GROUP_ID" \
        -var="user_public_key_path=$USER_PUBLIC_KEY_PATH" \
        -var="memory_in_gbs=$MEMORY_IN_GBS_X86" \
        -var="ocpus=$OCPUS_X86" \
        -var="environment_type=$ENVIRONMENT_TYPE" \
        -var="tag_namespace=$TAG_NAMESPACE" \
        -var="jitsi_tag_namespace=$JITSI_TAG_NAMESPACE" \
        -var="user=$SSH_USER" \
        -var="user_private_key_path=$USER_PRIVATE_KEY_PATH" \
        -var="postinstall_status_file=$POSTINSTALL_STATUS_FILE" \
        -var="load_balancer_bs_name=$BACKEND_SET_NAME" \
        -var="load_balancer_id=$LOAD_BALANCER_ID" \
        -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
        -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
        $ACTION_POST_PARAMS $TF_POST_PARAMS
  fi
  if [ $? -eq 0 ]; then
    oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_IP --region $ORACLE_REGION --file $LOCAL_IP_KEY
    if [ $? -eq 0 ]; then
      echo "Using new instance pool bucket state file generated from terraform apply"
    else
      echo "Failure fetching newly applied terraform state, instance pools may not be defined properly below"
    fi
  else
    echo "Failure in selenium grid instance pool terraform, exiting..."
    exit 5
  fi
fi

if [[ "$SELENIUM_GRID_NOMAD_ENABLED" == "true" ]]; then
  NODE_POOL_ID_X86="$(cat $LOCAL_IP_KEY | jq -r '.resources[]
      | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node_x86")
      | .instances[0].attributes.id')"

  if [ -z "$NODE_POOL_ID_X86" ]; then
    echo "NODE_POOL_ID_X86 failed to be found or created, exiting..."
    exit 4
  fi

  NODE_POOL_ID_ARM="$(cat $LOCAL_IP_KEY | jq -r '.resources[]
      | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node_arm")
      | .instances[0].attributes.id')"

  if [ -z "$NODE_POOL_ID_ARM" ]; then
    echo "NODE_POOL_ID_ARM failed to be found or created, exiting..."
    exit 4
  fi


else
  NODE_POOL_ID="$(cat $LOCAL_IP_KEY | jq -r '.resources[]
      | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_node")
      | .instances[0].attributes.id')"

  if [ -z "$NODE_POOL_ID" ]; then
    echo "NODE_POOL_ID failed to be found or created, exiting..."
    exit 4
  fi

  HUB_POOL_ID="$(cat $LOCAL_IP_KEY | jq -r '.resources[]
      | select(.type == "oci_core_instance_pool" and .name == "oci_instance_pool_hub")
      | .instances[0].attributes.id')"

  if [ -z "$HUB_POOL_ID" ]; then
    echo "HUB_POOL_ID failed to be found or created, exiting..."
    exit 3
  fi

fi