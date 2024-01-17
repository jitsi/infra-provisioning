#!/usr/bin/env bash
set -x
unset SSH_USER

if [ -z "$ANSIBLE_SSH_USER" ]; then
    if [  -z "$1" ]; then
        ANSIBLE_SSH_USER=$(whoami)
        echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
    else
        ANSIBLE_SSH_USER=$1
        echo "Run ansible as $ANSIBLE_SSH_USER"
    fi
fi
#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))
[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../../infra-configuration"

[ -z "$ROLE" ] && ROLE="haproxy"
[ -z "$NAME" ] && NAME="$ENVIRONMENT-$ORACLE_REGION-$ROLE"
[ -z "$ORACLE_GIT_BRANCH" ] && ORACLE_GIT_BRANCH="master"

[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found. Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../../clouds/${ORACLE_CLOUD_NAME}.sh

cd $ANSIBLE_BUILD_PATH
HAPROXY_INVENTORY='./haproxy.inventory'
echo '[tag_shard_role_haproxy]' > $HAPROXY_INVENTORY
$LOCAL_PATH/../../scripts/node.py --environment $ENVIRONMENT --role haproxy --region $ORACLE_REGION --batch  --oracle  --oracle_only>> $HAPROXY_INVENTORY

# build instance list for only this region
ansible-playbook ansible/stop-consul-services.yml \
-i "$HAPROXY_INVENTORY" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER"

cd -

[ -z "$S3_PROFILE" ] && S3_PROFILE="oracle"
[ -z "$S3_STATE_BUCKET" ] && S3_STATE_BUCKET="tf-state-$ENVIRONMENT"
[ -z "$S3_ENDPOINT" ] && S3_ENDPOINT="https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com"
[ -z "$S3_STATE_KEY" ] && S3_STATE_KEY="$ENVIRONMENT/haproxy-components/terraform.tfstate"


TERRAFORM_MAJOR_VERSION=$(terraform -v | head -1  | awk '{print $2}' | cut -d'.' -f1)
TF_GLOBALS_CHDIR=
if [[ "$TERRAFORM_MAJOR_VERSION" == "v1" ]]; then
  TF_GLOBALS_CHDIR="-chdir=$LOCAL_PATH/destroy"
  TF_CLI_ARGS=""
  TF_POST_PARAMS=
else
  TF_POST_PARAMS="$LOCAL_PATH/destroy"
fi

# delete the rule set
LOCAL_KEY="terraform-lb-rs.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY --region $ORACLE_REGION --file $LOCAL_KEY
if [ $? -eq 0 ]; then

    #The —reconfigure option disregards any existing configuration, preventing migration of any existing state
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
    -auto-approve $TF_POST_PARAMS
else
  echo "LB RULE SET failed to be deleted, not found"
fi


# delete the main stack
LOCAL_KEY="terraform-main.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY --region $ORACLE_REGION --file $LOCAL_KEY
if [ $? -eq 0 ]; then

    #The —reconfigure option disregards any existing configuration, preventing migration of any existing state
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
    -auto-approve $TF_POST_PARAMS
else
  echo "MAIN STACK failed to be deleted, not found"
fi



# next find or create the instance configuration
[ -z "$S3_STATE_KEY_IC" ] && S3_STATE_KEY_IC="$ENVIRONMENT/haproxy-components/terraform-ic.tfstate"

LOCAL_IC_KEY="terraform-ic.tfstate"


oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_IC --region $ORACLE_REGION --file $LOCAL_IC_KEY
if [ $? -eq 0 ]; then

  terraform $TF_GLOBALS_CHDIR init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_IC" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS


  terraform $TF_GLOBALS_CHDIR apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS

else
  echo "INSTANCE_CONFIGURATION failed to be deleted, not found"
fi


# first find or create the load balancer security group
[ -z "$S3_STATE_LB_KEY_SG" ] && S3_STATE_LB_KEY_SG="$ENVIRONMENT/haproxy-components/terraform-lb-sg.tfstate"
LOCAL_LB_KEY_SG="terraform-lb-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_LB_KEY_SG --region $ORACLE_REGION --file $LOCAL_LB_KEY_SG

if [ $? -eq 0 ]; then
  terraform $TF_GLOBALS_CHDIR init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_LB_KEY_SG" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS

  terraform $TF_GLOBALS_CHDIR apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS
else
    echo "LB_SECURITY_GROUP failed to be deleted, not found"
fi


# first find or create the haproxy security group
[ -z "$S3_STATE_KEY_HAPROXY_SG" ] && S3_STATE_KEY_HAPROXY_SG="$ENVIRONMENT/haproxy-components/terraform-haproxy-sg.tfstate"
LOCAL_HAPROXY_SG_KEY="terraform-haproxy-sg.tfstate"

oci os object get --bucket-name $S3_STATE_BUCKET --name $S3_STATE_KEY_HAPROXY_SG --region $ORACLE_REGION --file $LOCAL_HAPROXY_SG_KEY

if [ $? -eq 0 ]; then
  terraform $TF_GLOBALS_CHDIR init \
    -backend-config="bucket=$S3_STATE_BUCKET" \
    -backend-config="key=$S3_STATE_KEY_HAPROXY_SG" \
    -backend-config="region=$ORACLE_REGION" \
    -backend-config="profile=$S3_PROFILE" \
    -backend-config="endpoint=$S3_ENDPOINT" \
    -reconfigure $TF_POST_PARAMS

  terraform $TF_GLOBALS_CHDIR apply \
    -var="oracle_region=$ORACLE_REGION" \
    -var="tenancy_ocid=$TENANCY_OCID" \
    -auto-approve $TF_POST_PARAMS
else
  echo "HAPROXY_SECURITY_GROUP failed to be deleted, not found"
fi
