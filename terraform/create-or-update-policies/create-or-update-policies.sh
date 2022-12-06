#!/bin/bash
set -x #echo on

#load cloud defaults
[ -e ../all/clouds/all.sh ] && . ../all/clouds/all.sh

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "../all/clouds/oracle.sh" ] && . ../all/clouds/oracle.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found.  Exiting..."
  exit 1
fi

COMPARTMENT_NAME=$ENVIRONMENT
JIBRI_POLICY_NAME="$COMPARTMENT_NAME-jibris-policy"
RECOVERY_AGENT_POLICY_NAME="$COMPARTMENT_NAME-recovery-agent-policy"

###Find equivalent Oracle regions
REGIONS=()
for CLOUD_NAME in $RELEASE_CLOUDS; do
  source ../all/clouds/$CLOUD_NAME.sh
  if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION equivalent found for cloud ${CLOUD_NAME}, exiting..."
    exit 2
  fi
  REGIONS+=($ORACLE_REGION)
  unset ORACLE_REGION
done

#Consider eu-amsterdam-1 the home region to save the terraform state for policies
ORACLE_REGION=eu-amsterdam-1
ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "../all/clouds/${ORACLE_CLOUD_NAME}.sh" ] && . ../all/clouds/"${ORACLE_CLOUD_NAME}".sh

VCN_IDS=()

for REGION in "${REGIONS[@]}"; do
  VCN_NAME_ROOT="${REGION}-$ENVIRONMENT"
  VCN_NAME="$VCN_NAME_ROOT-vcn"

  VCN_DETAILS=$(oci network vcn list --region "${REGION}" --compartment-id "${COMPARTMENT_OCID}" --display-name "${VCN_NAME}" --all)
  VCN_ID=$(echo "$VCN_DETAILS" | jq -r '.data[0].id')
  if [ -z "$VCN_ID" ]; then
    echo "No VCN found for region ${REGION}, exiting..."
    exit 3
  fi
  VCN_IDS+=("$VCN_ID")
done

JIBRI_DYNAMIC_GROUP_NAME="$COMPARTMENT_NAME-jibri-dynamic-group"
RECOVERY_AGENT_DYNAMIC_GROUP_NAME="$COMPARTMENT_NAME-recovery-agent-dynamic-group"

# convert array to serialized list;
# this way you can use bash array as terraform list of string variable
REGIONS_WITH_QUOTES=()
for ENTRY in "${REGIONS[@]}"; do
  REGIONS_WITH_QUOTES+=("\"${ENTRY}\"")
done
REGION_LIST=$(
  IFS=,
  echo ["${REGIONS_WITH_QUOTES[*]}"]
)

if [ -z "$REGION_LIST" ] || [ "$REGION_LIST" == '[]' ]; then
  echo "Empty REGION_LIST. Exiting.."
  exit 3
fi

VCN_IDS_WITH_QUOTES=()
for ENTRY in "${VCN_IDS[@]}"; do
  VCN_IDS_WITH_QUOTES+=("\"${ENTRY}\"")
done
VCN_ID_LIST=$(
  IFS=,
  echo ["${VCN_IDS_WITH_QUOTES[*]}"]
)

if [ -z "$VCN_ID_LIST" ] || [ "$VCN_ID_LIST" == '[]' ]; then
  echo "Empty VCN_ID_LIST. Exiting.."
  exit 4
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://fr4eeztjonbe.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/policies/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=../all/bin/terraform/create-or-update-policies"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="../all/bin/terraform/create-or-update-policies"
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
  -var="compartment_name=$COMPARTMENT_NAME" \
  -var="compartment_id=$COMPARTMENT_OCID" \
  -var="jibri_policy_name=$JIBRI_POLICY_NAME" \
  -var="recovery_agent_policy_name=$RECOVERY_AGENT_POLICY_NAME" \
  -var="regions=$REGION_LIST" \
  -var="vcn_ids=$VCN_ID_LIST" \
  -var="jibri_dynamic_group_name=$JIBRI_DYNAMIC_GROUP_NAME" \
  -var="recovery_agent_dynamic_group_name=$RECOVERY_AGENT_DYNAMIC_GROUP_NAME" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
