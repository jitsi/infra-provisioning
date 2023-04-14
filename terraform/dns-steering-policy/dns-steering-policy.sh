#!/bin/bash

set -x
unset SSH_USER

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

[ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$GEO_DNS_ZONE_NAME"
[ -z "$TARGET_DNS_ZONE_NAME" ] && TARGET_DNS_ZONE_NAME="$ORACLE_DNS_ZONE_NAME"

if [ -z "$DNS_ZONE_NAME" ]; then
  echo "No DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

if [ -z "$TARGET_DNS_ZONE_NAME" ]; then
  echo "No TARGET_DNS_ZONE_NAME provided or found. Exiting..."
  exit 205
fi

DNS_NAME="$ENVIRONMENT.$DNS_ZONE_NAME"

STACK_REGION="us-phoenix-1"
if [ -z "$REGION_LIST" ]; then
  for R in $DRG_PEER_REGIONS; do
    if [[ "$R" != "eu-amsterdam-1" ]]; then
      REGION_IP="$(dig +short $ENVIRONMENT-$R-haproxy.$TARGET_DNS_ZONE_NAME)"
      if [ -z "$REGION_LIST" ]; then
        REGION_LIST="[\"$R\""
      else
        REGION_LIST="$REGION_LIST,\"$R\""
      fi
      if [ -z "$IP_MAP" ]; then
        IP_MAP="{\"$R\":\"$REGION_IP\""
      else
        IP_MAP="$IP_MAP,\"$R\":\"$REGION_IP\""
      fi
    fi
  done
  REGION_LIST="$REGION_LIST]"
  IP_MAP="$IP_MAP}"
fi

ORACLE_CLOUD_NAME="$STACK_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$STACK_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/dns-steering-policy/terraform.tfstate"

[ -z "$FALLBACK_REGION" ] && FALLBACK_REGION="us-ashburn-1"
FALLBACK_HOST_IP=$(dig +short $ENVIRONMENT-$FALLBACK_REGION-haproxy.$TARGET_DNS_ZONE_NAME)

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
  -backend-config="region=$STACK_REGION" \
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
  -var="domain=$DOMAIN" \
  -var="oracle_region=$STACK_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -var="compartment_ocid=$TENANCY_OCID" \
  -var="tag_namespace=$TAG_NAMESPACE" \
  -var="region_list=$REGION_LIST" \
  -var="ip_map=$IP_MAP" \
  -var="dns_name=$DNS_NAME" \
  -var="fallback_host=$FALLBACK_HOST_IP" \
  -var="dns_zone_name=$DNS_ZONE_NAME" \
  $ACTION_POST_PARAMS $TF_POST_PARAMS
