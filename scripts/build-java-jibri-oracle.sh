#!/bin/bash
set -x #echo on

#!/usr/bin/env bash
unset ANSIBLE_SSH_USER

[ -z "$JIBRI_BUILD_ID" ] && JIBRI_BUILD_ID="$BUILD_ID"
[ -z "$JIBRI_BUILD_ID" ] && JIBRI_BUILD_ID="standalone"


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
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

#use the latest build of JIBRI by default
if [ -z "$JIBRI_VERSION" ]; then
  JIBRI_VERSION='*'
else
  [ "$JIBRI_VERSION" == "*" ] || echo "$JIBRI_VERSION" | grep -q -- -1$ || JIBRI_VERSION="${JIBRI_VERSION}-1"
fi

[ -z "$FORCE_BUILD_IMAGE" ] && FORCE_BUILD_IMAGE=false

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_3"
[ -z "$OCPUS" ] && OCPUS="4"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"

EXISTING_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type JavaJibri --version "$JIBRI_VERSION" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ ! -z "$EXISTING_IMAGE_OCID" ]; then
  if $FORCE_BUILD_IMAGE; then
    echo "Jibri image already exists, but FORCE_BUILD_IMAGE is true so a new image with that same version will be build"
  else
    echo "Jibri image already exists. Exiting..."
    exit 0
  fi
fi

[ -z "$BASE_IMAGE_ID" ] && BASE_IMAGE_ID=$(scripts/oracle_custom_images.py --type JammyBase --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

# since focal, python is python3, so use that
[ -z "$SYSTEM_PYTHON" ] && SYSTEM_PYTHON="/usr/bin/python3"
# if bionic, use /usr/bin/python instead
#[ -z "$SYSTEM_PYTHON" ] && SYSTEM_PYTHON="/usr/bin/python"

if [ -z "$BASE_IMAGE_ID" ]; then
  echo "No BASE_IMAGE_ID provided or found. Exiting..."
fi

# addtional bastion configs
[ -z "$CONNECTION_SSH_PRIVATE_KEY_FILE" ] && CONNECTION_SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

usage() { echo "Usage: $0 [<username>]" 1>&2; }

usage

if [ -z "$1" ]; then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

# clean custom jibri images if limit is exceeded (may fail, but that's OK)
for CLEAN_ORACLE_REGION in $ORACLE_IMAGE_REGIONS; do
  echo "Cleaning images in $CLEAN_ORACLE_REGION"
  $LOCAL_PATH/oracle_custom_images.py --clean $ORACLE_CUSTOM_IMAGE_LIMIT --delete --region=$CLEAN_ORACLE_REGION --type=JavaJibri --compartment_id=$TENANCY_OCID;
done

# packer runs ansible using as hostname the 'default' string
# and caches the facts for that host to /tmp/fact.d/prod/default
# make sure to delete the cached facts, so they don't interfere with this run
rm -f .facts/default


# support packer 1.8
PACKER_VERSION=$(packer --version)
if [[ $(echo $PACKER_VERSION | cut -d'.' -f1) -ge 1 ]] && [[ $(echo $PACKER_VERSION | cut -d'.' -f2) -gt 7 ]]; then
  packer init $LOCAL_PATH/../build/require.pkr.hcl
fi

# on the base image, python points to python2 => python scripts will use python2 and will need boto3 installed for python2
# therefore run with ansible_python_interpreter /usr/bin/python to force ansible pip to use python2 and boto3 to be installed for python2
# this image is built per environment (e.g. the sidecar is enabled/disabled per environment)
packer build \
  -var "build_id=$JIBRI_BUILD_ID" \
  -var "environment=$ENVIRONMENT" \
  -var "ansible_build_path=$ANSIBLE_BUILD_PATH" \
  -var "ansible_ssh_user=$ANSIBLE_SSH_USER" \
  -var "base_image_ocid=$BASE_IMAGE_ID" \
  -var "jibri_deb_pkg_version=$JIBRI_VERSION" \
  -var "region=$ORACLE_REGION" \
  -var "availability_domain=$AVAILABILITY_DOMAIN" \
  -var "subnet_ocid=$PUBLIC_SUBNET_2_OCID" \
  -var "compartment_ocid=$TENANCY_OCID" \
  -var "shape=$SHAPE" \
  -var "ocpus=$OCPUS" \
  -var "memory_in_gbs=$MEMORY_IN_GBS" \
  -var "ansible_python_interpreter=$SYSTEM_PYTHON" \
  -var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
  -var "connection_ssh_bastion_host=$CONNECTION_SSH_BASTION_HOST" \
  -var "connection_ssh_private_key_file=$CONNECTION_SSH_PRIVATE_KEY_FILE" \
  -var "tag_namespace=$TAG_NAMESPACE" \
  -var "ansible_deploy_tags=$DEPLOY_TAGS" \
  -var "ansible_skip_tags=failfast" \
  $LOCAL_PATH/../build/build-java-jibri-oracle.json
