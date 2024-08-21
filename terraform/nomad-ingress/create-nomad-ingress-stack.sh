#!/bin/bash

set -x

LOCAL_PATH="$(dirname "${BASH_SOURCE[0]}")"
# creates a Nomad Ingress terraform stack in an environment/region

# check for ENVIRONMENT variable

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

# check for ORACLE_REGION variable

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

. $LOCAL_PATH/../../clouds/oracle.sh

# import site specific variables    
. $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh


ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
. $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/nomad-ingress/terraform.tfstate"

[ -z "$AVAILABILITY_DOMAINS" ] && AVAILABILITY_DOMAINS=$(oci iam availability-domain list --region=$ORACLE_REGION | jq .data[].name | jq --slurp .)
if [ -z "$AVAILABILITY_DOMAINS" ]; then
  echo "No AVAILABILITY_DOMAINS found.  Exiting..."
  exit 206
fi

ROLE="nomad-ingress"

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
  TF_CLI_ARGS=""
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
  -var="availability_domains=$AVAILABILITY_DOMAINS" \
  -var="role=$ROLE" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="public_subnet_ocid=$PUBLIC_SUBNET_OCID" \
  -var="environment_type=$ENVIRONMENT_TYPE" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="vcn_name=$VCN_NAME" \
  -var="load_balancer_shape=$LOAD_BALANCER_SHAPE" \
  -var="load_balancer_shape_details_maximum_bandwidth_in_mbps=$NOMAD_LOAD_BALANCER_MAXIMUM_BANDWIDTH_IN_MBPS" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
