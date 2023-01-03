#!/bin/bash
set -x
# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# e.g. ../all/bin/terraform/wavefront-proxy
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z $ENVIRONMENT ]; then
  echo "No ENVIRONMENT provided or found. Exiting..."
  exit 201
fi

if [ -z $GRID_NAME ]; then
  echo "No GRID_NAME provided or found. Exiting..."
  exit 202
fi

if [ -z $ORACLE_REGION ]; then
  echo "No ORACLE_REGION provided or found. Exiting..."
  exit 203
fi


# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ssh as $SSH_USER"
fi

[ -z "$ROLE" ] && ROLE="selenium-grid"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$GRID_NAME"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="main"

[ -e "../all/clouds/oracle.sh" ] && . ../all/clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "../all/clouds/${ORACLE_CLOUD_NAME}.sh" ] && . ../all/clouds/${ORACLE_CLOUD_NAME}.sh

# find hub and shutdown consul
HUB_IP=$($LOCAL_PATH/../../node.py --grid $GRID_NAME --role selenium-grid --grid_role hub --region $ORACLE_REGION --environment $ENVIRONMENT --batch)
if [ ! -z "$HUB_IP" ]; then
    echo "Found hub for $GRID_NAME in $ENVIRONMENT $ORACLE_REGION: $HUB_IP"
    ssh -F $LOCAL_PATH/../../config/ssh.config $SSH_USER@$HUB_IP sudo consul leave
    ssh -F $LOCAL_PATH/../../config/ssh.config $SSH_USER@$HUB_IP sudo service consul stop
    if [ $? -eq 0 ]; then
        echo "Consul stopped on hub for $GRID_NAME: $HUB_IP"
    else
        echo "ERROR stopping consul on hub, recreating this grid cause weird behavior for 3 days, unless the hub is removed from consul"
    fi
fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://fr4eeztjonbe.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
S3_STATE_BASE="$ENVIRONMENT/grid/$GRID_NAME/components"

[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"
[ -z "$S3_STATE_KEY_SG" ] && S3_STATE_KEY_SG="${S3_STATE_BASE}/terraform-sg.tfstate"
[ -z "$S3_STATE_KEY_IC" ] && S3_STATE_KEY_IC="${S3_STATE_BASE}/terraform-ic.tfstate"
[ -z "$S3_STATE_KEY_IP" ] && S3_STATE_KEY_IP="${S3_STATE_BASE}/terraform-ip.tfstate"
[ -z "$S3_STATE_KEY_LB" ] && S3_STATE_KEY_LB="${S3_STATE_BASE}/terraform-lb.tfstate"

[ -z "$DELETE_SECURITY_GROUP" ] && DELETE_SECURITY_GROUP="true"
[ -z "$DELETE_INSTANCE_CONFIGURATION" ] && DELETE_INSTANCE_CONFIGURATION="true"
[ -z "$DELETE_INSTANCE_POOL" ] && DELETE_INSTANCE_POOL="true"
[ -z "$DELETE_LOAD_BALANCER" ] && DELETE_LOAD_BALANCER="true"


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH/delete"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH/delete"
fi

if [ "$DELETE_INSTANCE_POOL" == "true" ]; then
    terraform $TF_GLOBALS_CHDIR init \
        -backend-config="bucket=$S3_STATE_BUCKET" \
        -backend-config="key=$S3_STATE_KEY_IP" \
        -backend-config="region=$ORACLE_REGION" \
        -backend-config="profile=$S3_PROFILE" \
        -backend-config="endpoint=$S3_ENDPOINT" \
        -reconfigure $TF_POST_PARAMS

    terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

fi

if [ "$DELETE_LOAD_BALANCER" == "true" ]; then
    terraform $TF_GLOBALS_CHDIR init \
        -backend-config="bucket=$S3_STATE_BUCKET" \
        -backend-config="key=$S3_STATE_KEY_LB" \
        -backend-config="region=$ORACLE_REGION" \
        -backend-config="profile=$S3_PROFILE" \
        -backend-config="endpoint=$S3_ENDPOINT" \
        -reconfigure $TF_POST_PARAMS

    terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

fi


if [ "$DELETE_INSTANCE_CONFIGURATION" == "true" ]; then
    terraform $TF_GLOBALS_CHDIR init \
        -backend-config="bucket=$S3_STATE_BUCKET" \
        -backend-config="key=$S3_STATE_KEY_IC" \
        -backend-config="region=$ORACLE_REGION" \
        -backend-config="profile=$S3_PROFILE" \
        -backend-config="endpoint=$S3_ENDPOINT" \
        -reconfigure $TF_POST_PARAMS

    terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

fi

if [ "$DELETE_SECURITY_GROUP" == "true" ]; then
    terraform $TF_GLOBALS_CHDIR init \
        -backend-config="bucket=$S3_STATE_BUCKET" \
        -backend-config="key=$S3_STATE_KEY_SG" \
        -backend-config="region=$ORACLE_REGION" \
        -backend-config="profile=$S3_PROFILE" \
        -backend-config="endpoint=$S3_ENDPOINT" \
        -reconfigure $TF_POST_PARAMS

    terraform $TF_GLOBALS_CHDIR destroy \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

fi
