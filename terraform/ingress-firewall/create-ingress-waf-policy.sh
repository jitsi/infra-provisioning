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
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

# first find or create the waf policy
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/ingress-waf/terraform.tfstate"
LOCAL_STATE_KEY="terraform.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY --region $ORACLE_REGION --file $LOCAL_STATE_KEY

# check to see if it's been created
if [ $? -eq 0 ]; then
  WAF_POLICY_ID="$(cat $LOCAL_STATE_KEY | jq -r '.resources[]
      | select(.type == "oci_waf_web_app_firewall_policy")
      | .attributes.id')"
fi

if [ -z "$WAF_POLICY_ID" ]; then
  terraform $TF_GLOBALS_CHDIR_SG init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE" \
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

  oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY --region $ORACLE_REGION --file $LOCAL_STATE_KEY

  WAF_POLICY_ID="$(cat $LOCAL_WAF_POLICY_KEY | jq -r '.resources[]
      | select(.type == "oci_waf_web_app_firewall_policy")
      | .attributes.id')"
fi

if [ -z "$WAF_POLICY_ID" ]; then
  echo "WAF_POLICY_ID failed to be found or created, exiting..."
  exit 3
fi