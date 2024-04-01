#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ROLE" ] && ROLE="nomad-pool-shared"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"

RESOURCE_NAME_ROOT="${NAME}"

[ -e "$LOCAL_PATH/../../clouds/all.sh" ] && . $LOCAL_PATH/../../clouds/all.sh
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi


ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

# create network security group for environment and oracle region

EPHEMERAL_INGRESS_CIDR="10.0.0.0/8"

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/nomad-shared-nsg/terraform.tfstate"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH"
else
  TF_POST_PARAMS="$LOCAL_PATH"
fi

[ -z "$ACTION" ] && ACTION="apply"

if [[ "$ACTION" == "apply" ]]; then
  ACTION_POST_PARAMS="-auto-approve"
fi
if [[ "$ACTION" == "import" ]]; then
  ACTION_POST_PARAMS="$1 $2"
fi

terraform $TF_GLOBALS_CHDIR init \
-backend-config="bucket=$S3_STATE_BUCKET" \
-backend-config="key=$S3_STATE_KEY" \
-backend-config="region=$ORACLE_REGION" \
-backend-config="profile=$S3_PROFILE" \
-backend-config="endpoint=$S3_ENDPOINT" \
-reconfigure $TF_POST_PARAMS

terraform $TF_GLOBALS_CHDIR apply \
-var="oracle_region=$ORACLE_REGION" \
-var="tenancy_ocid=$TENANCY_OCID" \
-var="compartment_ocid=$COMPARTMENT_OCID" \
-var="vcn_name=$VCN_NAME" \
-var="resource_name_root=$RESOURCE_NAME_ROOT" \
-var="ephemeral_ingress_cidr=$EPHEMERAL_INGRESS_CIDR" \
$ACTION_POST_PARAMS $TF_POST_PARAMS
