#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z $POOL_TYPE ]; then
  echo "No POOL_TYPE provided or found. Exiting..."
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

[ -z "$ROLE" ] && ROLE="nomad"
[ -z "$POOL_TYPE" ] && POOL_TYPE="general"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE-$POOL_TYPE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

# find pool and shutdown consul
# HUB_IPS=$($LOCAL_PATH/../../node.py --role $ROLE --pool_type $POOL_TYPE --region $ORACLE_REGION --environment $ENVIRONMENT --batch)
# if [ ! -z "$HUB_IPS" ]; then
#     echo "Found pools for $POOL_TYPE in $ENVIRONMENT $ORACLE_REGION: $HUB_IPS"
#     for HUB_IP in $HUP_IPS; do
#         ssh -F $LOCAL_PATH/../../../ssh.config $SSH_USER@$HUB_IP "sudo service nomad stop && sudo service consul stop"
#         if [ $? -eq 0 ]; then
#             echo "nomad and consul stopped on instances for $GRID_NAME: $HUB_IP"
#         else
#             echo "ERROR stopping consul on hub, recreating this grid cause weird behavior for 3 days, unless the hub is removed from consul"
#         fi
#     done
# fi

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://fr4eeztjonbe.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
S3_STATE_BASE="$ENVIRONMENT/nomad-instance-pool/$POOL_TYPE"

[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="${S3_STATE_BASE}/terraform.tfstate"
[ -z "$S3_STATE_KEY_SG" ] && S3_STATE_KEY_SG="${S3_STATE_BASE}/terraform-nomad-sg.tfstate"

[ -z "$DELETE_SECURITY_GROUP" ] && DELETE_SECURITY_GROUP="true"
[ -z "$DELETE_POOL" ] && DELETE_POOL="true"

TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH/delete"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH/delete"
fi
#The —reconfigure option disregards any existing configuration, preventing migration of any existing state


if [ "$DELETE_POOL" == "true" ]; then
    terraform $TF_GLOBALS_CHDIR init \
        -backend-config="bucket=$S3_STATE_BUCKET" \
        -backend-config="key=$S3_STATE_KEY" \
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

