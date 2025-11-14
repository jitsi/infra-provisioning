#!/bin/bash
set -x #echo on
#!/usr/bin/env bash

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
[ -z "$INFRA_CONFIGURATION_REPO" ] && INFRA_CONFIGURATION_REPO="$PRIVATE_CONFIGURATION_REPO"
[ -z "$INFRA_CONFIGURATION_REPO" ] && INFRA_CONFIGURATION_REPO="https://github.com/jitsi/infra-configuration.git"

[ -z "$INFRA_CUSTOMIZATIONS_REPO" ] && INFRA_CUSTOMIZATIONS_REPO="$PRIVATE_CUSTOMIZATIONS_REPO"
[ -z "$INFRA_CUSTOMIZATIONS_REPO" ] && INFRA_CUSTOMIZATIONS_REPO="https://github.com/jitsi/infra-customizations.git"

[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$REBUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$BUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID="standalone"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
#pull in cloud-specific variables, e.g. tenancy
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

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_5"
[ -z "$OCPUS" ] && OCPUS="4"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"


arch_from_shape $SHAPE

if [[ "$IMAGE_ARCH" == "aarch64" ]]; then
  BARE_IMAGE_ID="$ARM_OL8_BARE_IMAGE_ID"
fi

# TODO query available standard images with oracle linux 8
[ -z "$BARE_IMAGE_ID" ] && BARE_IMAGE_ID=$OL8_BARE_IMAGE_ID
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="OL8Bare"

EXISTING_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type OL8Base --version "latest" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ ! -z "$EXISTING_IMAGE_OCID" ]; then
  if $FORCE_BUILD_IMAGE; then
    echo "Base image already exists, but FORCE_BUILD_IMAGE is true so a new image with that same version will be build"
  else
    echo "Base image already exists and FORCE_BUILD_IMAGE is false. Exiting..."
    exit 0
  fi
fi

# addtional bastion configs
[ -z "$CONNECTION_SSH_PRIVATE_KEY_FILE" ] && CONNECTION_SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

# packer runs ansible using as hostname the 'default' string
# and caches the facts for that host to /tmp/fact.d/prod/default
# make sure to delete the cached facts, so they don't interfere with this run
rm -f .facts/default

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

# support packer 1.8
PACKER_VERSION=$(packer --version)
echo $PACKER_VERSION | grep -q 'Packer' && PACKER_VERSION=$(echo $PACKER_VERSION | cut -d' ' -f2 | cut -d 'v' -f2)
if [[ $(echo $PACKER_VERSION | cut -d'.' -f1) -ge 1 ]] && [[ $(echo $PACKER_VERSION | cut -d'.' -f2) -gt 7 ]]; then
  packer init $LOCAL_PATH/../build/require.pkr.hcl
fi

packer build \
-var "build_id=$ANSIBLE_BUILD_ID" \
-var "environment=$ENVIRONMENT" \
-var "ansible_ssh_user=opc" \
-var "ansible_build_path=$ANSIBLE_BUILD_PATH" \
-var "base_image_type=$BASE_IMAGE_TYPE" \
-var "base_image_ocid=$BARE_IMAGE_ID" \
-var "image_architecture=$IMAGE_ARCH" \
-var "region=$ORACLE_REGION" \
-var "availability_domain=$AVAILABILITY_DOMAIN" \
-var "subnet_ocid=$NAT_SUBNET_OCID" \
-var "compartment_ocid=$TENANCY_OCID" \
-var "type=OL8Base" \
-var "shape=$SHAPE" \
-var "ocpus=$OCPUS" \
-var "memory_in_gbs=$MEMORY_IN_GBS" \
-var "ansible_deploy_tags=$DEPLOY_TAGS" \
-var "ansible_skip_tags=failfast" \
-var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
-var "tag_namespace=$TAG_NAMESPACE" \
-var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
-var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
$LOCAL_PATH/../build/build-base-ol8-oracle.json

RET=$?

if [[ $RET -eq 0 ]]; then
  IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type OL8Base --version "latest" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
  $LOCAL_PATH/../scripts/oracle_custom_images.py --add_shape_compatibility --image_id $IMAGE_OCID --region $ORACLE_REGION
fi

exit $RET