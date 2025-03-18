#!/bin/bash
LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e $LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$VCN_NAME" ] && VCN_NAME="$ORACLE_REGION-$ENVIRONMENT-vcn"

[ -z "$DB_SYSTEM_INSTANCE_COUNT" ] && DB_SYSTEM_INSTANCE_COUNT=1
[ -z "$DB_SYSTEM_INSTANCE_MEMORY_IN_GBS" ] && DB_SYSTEM_INSTANCE_MEMORY_IN_GBS=32
[ -z "$DB_SYSTEM_INSTANCE_OCPUS" ] && DB_SYSTEM_INSTANCE_OCPUS=2


[ -z "$DB_SYSTEM_SHAPE" ] && DB_SYSTEM_SHAPE="PostgreSQL.VM.Standard.E5.Flex"

set -x

[ -z "$VAULT_ID" ] && VAULT_ID="$(oci kms management vault list --compartment-id $COMPARTMENT_OCID --region $ORACLE_REGION | jq -r '.data[]|select(."lifecycle-state"=="ACTIVE" and ."defined-tags"."jitsi"."environment"=="'$ENVIRONMENT'" and ."defined-tags"."jitsi"."shard-role"=="nomad-general-vault")|.id')"
if [[ $? -ne 0 ]]; then
  echo "Failed to get vault ID for compartment $COMPARTMENT_OCID in region $ORACLE_REGION"
  exit 1
fi

if [ -z "$OPS_PEER_CIDRS" ]; then
  OPS_PEER_CIDRS="[]"
fi

if [ -n "$EXTRA_OPS_PEER_CIDRS" ]; then
  OPS_PEER_CIDRS="$(echo "$OPS_PEER_CIDRS" "$EXTRA_OPS_PEER_CIDRS"  | jq -s '.|add')"
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/nomad-psql/terraform.tfstate"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_POLICY_ENDPOINT" ] && S3_POLICY_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$TENANCY_REGION.oraclecloud.com"
[ -z "$S3_POLICY_STATE_KEY" ] && S3_POLICY_STATE_KEY="$ENVIRONMENT/nomad-psql-policy/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
TF_POLICY_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_POLICY_GLOBALS_CHDIR="-chdir=$LOCAL_PATH/policies"
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH"
  TF_POLICY_POST_PARAMS="$LOCAL_PATH/policies"
fi

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

# # The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_POLICY_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_POLICY_STATE_KEY" \
  -backend-config="region=$TENANCY_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_POLICY_ENDPOINT" \
  -reconfigure \
  $TF_POLICY_POST_PARAMS

terraform $TF_POLICY_GLOBALS_CHDIR $ACTION \
  -var="environment=$ENVIRONMENT" \
  -var="oracle_region=$TENANCY_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  $ACTION_POST_PARAMS $TF_POLICY_POST_PARAMS

# # The —reconfigure option disregards any existing configuration, preventing migration of any existing state
terraform $TF_GLOBALS_CHDIR init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -reconfigure \
  $TF_POST_PARAMS

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="environment=$ENVIRONMENT" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="vcn_name=$VCN_NAME" \
  -var="db_system_instance_count=$DB_SYSTEM_INSTANCE_COUNT" \
  -var="db_system_instance_memory_size_in_gbs=$DB_SYSTEM_INSTANCE_MEMORY_IN_GBS" \
  -var="db_system_instance_ocpu_count=$DB_SYSTEM_INSTANCE_OCPUS" \
  -var="db_system_shape=$DB_SYSTEM_SHAPE" \
  -var="subnet_ocid=$NAT_SUBNET_OCID" \
  -var="vault_id=$VAULT_ID" \
  -var="ops_peer_cidrs=$OPS_PEER_CIDRS" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
