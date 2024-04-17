#!/usr/bin/env bash
set -x
unset SSH_USER

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 2
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 2
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

RESOURCE_NAME_ROOT="${NAME_ROOT}"

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

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/ingress-waf/terraform.tfstate"


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
  TF_POST_PARAMS_SG=
  TF_POST_PARAMS_LBSG=
  TF_POST_PARAMS_RS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

# first find or create the waf policy
[ -z "$S3_WAF_POLICY_KEY" ] && S3_STATE_KEY_HAPROXY_SG="$ENVIRONMENT/ingress-waf/terraform-ingress-waf-policy.tfstate"
LOCAL_WAF_POLICY_KEY="terraform-ingress-waf-policy.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_WAF_POLICY_KEY --region $ORACLE_REGION --file $LOCAL_WAF_POLICY_KEY

#### CHECK TO SEE IF IT'S ALREADY CREATED
#if [ $? -eq 0 ]; then
#  HAPROXY_SECURITY_GROUP_ID="$(cat $LOCAL_HAPROXY_SG_KEY | jq -r '.resources[]
#      | select(.type == "oci_core_network_security_group")
#      | .instances[]
#      | .attributes.id')"
#fi

WAF_POLICY_ID="true"

if [ -z "$WAF_POLICY_ID" ]; then
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




## next create one waf per region / load balancer (all public lbs)



###### ignore copypasta below

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
  -var="signal_api_lb_hostnames=$SIGNAL_API_LB_HOSTNAME_JSON" \
  -var="signal_api_hostname=$SIGNAL_API_HOSTNAME" \
  -var="signal_api_certificate_certificate_name=$SIGNAL_API_CERTIFICATE_NAME" \
  -var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
  -var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS

LOCAL_HAPROXY_KEY="terraform-haproxy.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY --region $ORACLE_REGION --file $LOCAL_HAPROXY_KEY
if [ $? -eq 0 ]; then
  OCI_LOAD_BALANCER_ID="$(cat $LOCAL_HAPROXY_KEY | jq -r '.resources[]
      | select(.type == "oci_load_balancer")
      | .instances[]
      | .attributes.id')"
else
  echo "Failed to extract load balancer ID, redirect ruleset will not be applied."
  exit 12
fi

# find or create the load balancer rule set for https redirect
# this is a separate terraform template because updating the load balancer
# ruleset causes the load balancer to drop active connections
[ -z "$S3_STATE_LB_KEY_RS" ] && S3_STATE_LB_KEY_RS="$ENVIRONMENT/haproxy-components/terraform-lb-rs.tfstate"
LOCAL_LB_KEY_RS="terraform-lb-rs.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_LB_KEY_RS --region $ORACLE_REGION --file $LOCAL_LB_KEY_RS

if [ $? -eq 0 ]; then
  LB_RULE_SET_ID="$(cat $LOCAL_LB_KEY_RS | jq -r '.resources[]
      | select(.type == "oci_load_balancer_rule_set")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$LB_RULE_SET_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_RS init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_LB_KEY_RS" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS_RS

  terraform $TF_GLOBALS_CHDIR_RS apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -var="oci_load_balancer_id=$OCI_LOAD_BALANCER_ID" \
    -var="oci_load_balancer_bs_name=HAProxyLBBS" \
    -var="oci_load_balancer_redirect_rule_set_name=RedirectToHTTPS" \
    -auto-approve $TF_POST_PARAMS_RS

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_LB_KEY_RS --region $ORACLE_REGION --file $LOCAL_LB_KEY_RS

  LB_RULE_SET_ID="$(cat $LOCAL_LB_KEY_RS | jq -r '.resources[]
      | select(.type == "oci_core_network_security_group")
      | .instances[]
      | .attributes.id')"
fi

if [ -z "$LB_RULE_SET_ID" ]; then
  echo "LB_RULE_SET_ID failed to be found or created, exiting..."
  exit 3
fi