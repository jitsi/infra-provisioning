#!/bin/bash
set -x #echo on

#!/usr/bin/env bash
unset ANSIBLE_SSH_USER

[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$REBUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$BUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID="standalone"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration/ansible"

if [ ! -d "$ANSIBLE_BUILD_PATH" ]; then
  echo "ANSIBLE_BUILD_PATH $ANSIBLE_BUILD_PATH expected to exist, exiting..."
  exit 202
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

[ -z "$FORCE_BUILD_IMAGE" ] && FORCE_BUILD_IMAGE=false

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$IMAGE_ARCH" ] && IMAGE_ARCH="x86_64"

if [[ "$IMAGE_ARCH" == "aarch64" ]]; then
  [ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"
fi

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"
[ -z "$OCPUS" ] && OCPUS="8"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"

TAG_NAMESPACE="jitsi"

arch_from_shape $SHAPE

EXISTING_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type coTURN --version "latest" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ ! -z "$EXISTING_IMAGE_OCID" ]; then
  if $FORCE_BUILD_IMAGE; then
    echo "Coturn image already exists, but FORCE_BUILD_IMAGE is true so a new image with that same version will be build"
  else
    echo "Coturn image already exists. Exiting..."
    exit 0
  fi
fi

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$COTURN_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="JammyBase"

[ -z "$BASE_IMAGE_ID" ] && BASE_IMAGE_ID=$($LOCAL_PATH/oracle_custom_images.py --type $BASE_IMAGE_TYPE  --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

# addtional bastion configs
[ -z "$CONNECTION_SSH_PRIVATE_KEY_FILE" ] && CONNECTION_SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

usage() { echo "Usage: $0 [<username>]" 1>&2; }

usage

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi


DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

# packer runs ansible using as hostname the 'default' string
# and caches the facts for that host to /tmp/fact.d/prod/default
# make sure to delete the cached facts, so they don't interfere with this run
rm -f .facts/default

# support packer 1.8
PACKER_VERSION=$(packer --version)
if [[ $(echo $PACKER_VERSION | cut -d'.' -f1) -ge 1 ]] && [[ $(echo $PACKER_VERSION | cut -d'.' -f2) -gt 7 ]]; then
  packer init $LOCAL_PATH/../build/require.pkr.hcl
fi

# run as python2, as postinstall also seems to run with interpreter python2
#TODO delete oldest coturn image if no space is available
packer build \
-var "build_id=$ANSIBLE_BUILD_ID" \
-var "environment=$ENVIRONMENT" \
-var "ansible_build_path=$ANSIBLE_BUILD_PATH" \
-var "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-var "image_architecture=$IMAGE_ARCH" \
-var "base_image_type=$BASE_IMAGE_TYPE" \
-var "base_image_ocid=$BASE_IMAGE_ID" \
-var "region=$ORACLE_REGION" \
-var "availability_domain=$AVAILABILITY_DOMAIN" \
-var "subnet_ocid=$NAT_SUBNET_OCID" \
-var "compartment_ocid=$TENANCY_OCID" \
-var "shape=$SHAPE" \
-var "ocpus=$OCPUS" \
-var "memory_in_gbs=$MEMORY_IN_GBS" \
-var "ansible_python_interpreter=/usr/bin/python" \
-var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
-var "connection_ssh_bastion_host=$CONNECTION_SSH_BASTION_HOST" \
-var "connection_ssh_private_key_file=$CONNECTION_SSH_PRIVATE_KEY_FILE" \
-var "tag_namespace=$TAG_NAMESPACE" \
-var "ansible_deploy_tags=$DEPLOY_TAGS" \
$LOCAL_PATH/../build/build-coturn-oracle.json
