#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

set -x

# Create Security Lists
[ -z "$NAME_ROOT" ] && NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"

if [ -z "$OPS_PEER_CIDRS" ]; then
  echo "No OPS_PEER_CIDRS found.  Exiting..."
  exit 204
fi

if [ -n "$EXTRA_OPS_PEER_CIDRS" ]; then
  OPS_PEER_CIDRS="$(echo "$OPS_PEER_CIDRS" "$EXTRA_OPS_PEER_CIDRS"  | jq -s '.|add')"
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"

S3_STATE_BASE="$ENVIRONMENT/vcn-security-lists"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"


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
  [ -z "$IMPORT_LOOKUP_FLAG" ] && IMPORT_LOOKUP_FLAG="true"
  if [ "$IMPORT_LOOKUP_FLAG" == "true" ]; then
    SECURITY_LIST_OCID="$(oci network security-list list --compartment-id $COMPARTMENT_OCID --all --region $ORACLE_REGION --display-name $NAME_ROOT-PrivateSecurityList | jq -r '.data[].id')"
    if [[ "$SECURITY_LIST_OCID" == "null" ]]; then
        echo "No security list found, not automatically providing import parameters"
        ACTION_POST_PARAMS="$1 $2"
    else
        ACTION_POST_PARAMS="oci_core_security_list.private_security_list $SECURITY_LIST_OCID"
    fi
    ACTION_POST_PARAMS="oci_core_security_list.private_security_list $SECURITY_LIST_OCID"
  else
    ACTION_POST_PARAMS="$1 $2"
  fi
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="oracle_region=$ORACLE_REGION"\
  -var="tenancy_ocid=$TENANCY_OCID"\
  -var="compartment_ocid=$COMPARTMENT_OCID"\
  -var="environment=$ENVIRONMENT"\
  -var="vcn_name=$VCN_NAME"\
  -var="resource_name_root=$NAME_ROOT"\
  -var="ops_peer_cidrs=$OPS_PEER_CIDRS"\
  $ACTION_POST_PARAMS $TF_POST_PARAMS