#!/bin/bash
set -x #echo on

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$CLOUD_NAME" ]; then
  echo "No CLOUD_NAME provided or found. Exiting .."
  exit 202
fi

# We need an envirnment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 203
fi

[ -e "$LOCAL_PATH/../../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${CLOUD_NAME}.sh

AWS_VIRTUAL_PRIVATE_GATEWAY_ASN="$EC2_AWS_ASN"
[ -z "$AWS_VIRTUAL_PRIVATE_GATEWAY_ASN" ] && AWS_VIRTUAL_PRIVATE_GATEWAY_ASN="64512"

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 204
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-vpn"

VCN_NAME_ROOT="$ORACLE_REGION-$ENVIRONMENT"
VCN_NAME="$VCN_NAME_ROOT-vcn"


if [ -z "$AWS_TUNNEL_1_PRE_SHARED_KEY" ]; then
  echo "No AWS_TUNNEL_1_PRE_SHARED_KEY found.  Exiting..."
  exit 205
fi

if [ -z "$AWS_TUNNEL_1_IP_ADDRESS" ]; then
  echo "No AWS_TUNNEL_1_IP_ADDRESS found.  Exiting..."
  exit 206
fi

if [ -z "$AWS_TUNNEL_1_VIRTUAL_PRIVATE_GATEWAY" ]; then
  echo "No AWS_TUNNEL_1_VIRTUAL_PRIVATE_GATEWAY found.  Exiting..."
  exit 207
fi

if [ -z "$AWS_TUNNEL_1_CUSTOMER_GATEWAY" ]; then
  echo "No AWS_TUNNEL_1_CUSTOMER_GATEWAY found.  Exiting..."
  exit 208
fi

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then

  if [ -z "$AWS_TUNNEL_2_PRE_SHARED_KEY" ]; then
    echo "No AWS_TUNNEL_2_PRE_SHARED_KEY found.  Exiting..."
    exit 209
  fi

  if [ -z "$AWS_TUNNEL_2_IP_ADDRESS" ]; then
    echo "No AWS_TUNNEL_2_IP_ADDRESS found.  Exiting..."
    exit 210
  fi

  if [ -z "$AWS_TUNNEL_2_VIRTUAL_PRIVATE_GATEWAY" ]; then
    echo "No AWS_TUNNEL_2_VIRTUAL_PRIVATE_GATEWAY found.  Exiting..."
    exit 211
  fi

  if [ -z "$AWS_TUNNEL_2_CUSTOMER_GATEWAY" ]; then
    echo "No AWS_TUNNEL_2_CUSTOMER_GATEWAY found.  Exiting..."
    exit 212
  fi
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/vpns/$NAME/terraform.tfstate"

if [ -z "$SINGLE_CONNECTION_FLAG" ]; then
  TF_PATH="$LOCAL_PATH"
else
  TF_PATH="$LOCAL_PATH/../create-vpn-oracle-ipsec-tunnel-single-connection"
fi

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
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
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR $ACTION \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$COMPARTMENT_OCID" \
  -var="oracle_region=$ORACLE_REGION" \
  -var="vcn_name=$VCN_NAME" \
  -var="resource_name_root=$VCN_NAME_ROOT" \
  -var="bgp_asn=$AWS_VIRTUAL_PRIVATE_GATEWAY_ASN" \
  -var="tunnel_1_ipsec_customer_interface_ip=$AWS_TUNNEL_1_VIRTUAL_PRIVATE_GATEWAY" \
  -var="tunnel_1_ipsec_oracle_interface_ip=$AWS_TUNNEL_1_CUSTOMER_GATEWAY" \
  -var="tunnel_1_ip_address=$AWS_TUNNEL_1_IP_ADDRESS" \
  -var="tunnel_1_shared_secret=$AWS_TUNNEL_1_PRE_SHARED_KEY" \
  -var="tunnel_2_ipsec_customer_interface_ip=$AWS_TUNNEL_2_VIRTUAL_PRIVATE_GATEWAY" \
  -var="tunnel_2_ipsec_oracle_interface_ip=$AWS_TUNNEL_2_CUSTOMER_GATEWAY" \
  -var="tunnel_2_ip_address=$AWS_TUNNEL_2_IP_ADDRESS" \
  -var="tunnel_2_shared_secret=$AWS_TUNNEL_2_PRE_SHARED_KEY" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
