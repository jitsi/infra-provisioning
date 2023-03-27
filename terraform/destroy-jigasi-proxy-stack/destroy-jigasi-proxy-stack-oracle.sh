#!/bin/bash
set -e
set -x #echo on

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"

[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"

[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"

[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/jigasi-proxy-components/terraform.tfstate"

cd $LOCAL_PATH
rm -rf .terraform
#Use -force-copy option to answer "yes" to the migration question, to confirm migration of workspace states
terraform init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -force-copy

terraform destroy \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -auto-approve

DESTROY_MAIN=$?


[ -z "$S3_STATE_KEY_JIGASI_PROXY_SG" ] && S3_STATE_KEY_JIGASI_PROXY_SG="$ENVIRONMENT/jigasi-proxy-components/terraform-jigasi-proxy-sg.tfstate"
rm -rf .terraform
#Use -force-copy option to answer "yes" to the migration question, to confirm migration of workspace states
terraform init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY_JIGASI_PROXY_SG" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -force-copy

terraform destroy \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -auto-approve

DESTROY_JIGASI_PROXY_SG=$?

[ -z "$S3_STATE_KEY_LB_SG" ] && S3_STATE_KEY_LB_SG="$ENVIRONMENT/jigasi-proxy-components/terraform-jigasi-lb-sg.tfstate"
rm -rf .terraform
#Use -force-copy option to answer "yes" to the migration question, to confirm migration of workspace states
terraform init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY_LB_SG" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -force-copy

terraform destroy \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -auto-approve

S3_STATE_KEY_LB_SG=$?

[ -z "$S3_STATE_KEY_IC" ] && S3_STATE_KEY_IC="$ENVIRONMENT/jigasi-proxy-components/terraform-ic.tfstate"
rm -rf .terraform
#Use -force-copy option to answer "yes" to the migration question, to confirm migration of workspace states
terraform init \
  -backend-config="bucket=$S3_STATE_BUCKET" \
  -backend-config="key=$S3_STATE_KEY_IC" \
  -backend-config="region=$ORACLE_REGION" \
  -backend-config="profile=$S3_PROFILE" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -force-copy

terraform destroy \
  -var="oracle_region=$ORACLE_REGION" \
  -var="tenancy_ocid=$TENANCY_OCID" \
  -auto-approve

DESTROY_IC=$?


if [ $DESTROY_MAIN -eq 0 ]; then
  echo "Terraform succeeded, exiting cleanly"
  exit 0
else
  echo "Terraform failed to delete cleanly, dumping existing state"
  # list existing instances in shard
  terraform show -json
  # sleep requisite time
  sleep 1200
  # re-run terraform destroy command
  terraform destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve

  exit $?
fi
