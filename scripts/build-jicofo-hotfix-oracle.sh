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

[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$REBUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$BUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID="standalone"

if [ -z "$INFRA_CONFIGURATION_REPO" ]; then
  echo "No INFRA_CONFIGURATION_REPO set, exiting..."
  exit 203
fi

if [ -z "$INFRA_CUSTOMIZATIONS_REPO" ]; then
  echo "No INFRA_CUSTOMIZATIONS_REPO set, exiting..."
  exit 203
fi

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$BASE_SIGNAL_VERSION" ]; then
  echo "No BASE_SIGNAL_VERSION found.  Exiting..."
  exit 205
fi

if [ -z "$JICOFO_VERSION" ]; then
  echo "No JICOFO_VERSION found.  Exiting..."
  exit 205
fi

JITSI_MEET_VERSION=$(echo $BASE_SIGNAL_VERSION | cut -d'-' -f2)
PROSODY_VERSION=$(echo $BASE_SIGNAL_VERSION | cut -d'-' -f3)

[ -z "$ENVIRONMENT" ] && ENVIRONMENT="prod"
[ -z "$TAG_NAMESPACE" ] && TAG_NAMESPACE="jitsi"
[ -z "$CONNECTION_USE_PRIVATE_IP" ] && CONNECTION_USE_PRIVATE_IP=false


[ -z "$FORCE_BUILD_IMAGE" ] && FORCE_BUILD_IMAGE=false

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$IMAGE_ARCH" ] && IMAGE_ARCH="aarch64"

if [[ "$IMAGE_ARCH" == "aarch64" ]]; then
  [ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"
fi

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_5"
[ -z "$OCPUS" ] && OCPUS="4"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="16"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="Signal"

arch_from_shape $SHAPE

[ -z "$BASE_IMAGE_ID" ] && BASE_IMAGE_ID=$($LOCAL_PATH/oracle_custom_images.py --architecture "$IMAGE_ARCH" --type $BASE_IMAGE_TYPE --version $BASE_SIGNAL_VERSION --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

DEB_JICOFO_VERSION="$JICOFO_VERSION"
[ "$DEB_JICOFO_VERSION" == "*" ] || echo $DEB_JICOFO_VERSION | grep -q "1\.0" || DEB_JICOFO_VERSION="1.0-${DEB_JICOFO_VERSION}-1"
[ "$DEB_JICOFO_VERSION" == "*" ] || echo $DEB_JICOFO_VERSION | grep -q -- -1$ || DEB_JICOFO_VERSION="${DEB_JICOFO_VERSION}-1"

SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"

EXISTING_IMAGE_OCID=$($LOCAL_PATH/oracle_custom_images.py --type Signal --version "$SIGNAL_VERSION" --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
if [ ! -z "$EXISTING_IMAGE_OCID" ]; then
  if $FORCE_BUILD_IMAGE; then
    echo "Signal image version $SIGNAL_VERSION already exists, but FORCE_BUILD_IMAGE is true so a new image with that same version will be build"
  else
    echo "Signal image version $SIGNAL_VERSION already exists and FORCE_BUILD_IMAGE is false. Exiting..."
    exit 0
  fi
fi

# run as user
if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi
[ -z "$CONNECTION_SSH_PRIVATE_KEY_FILE" ] && CONNECTION_SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="oracle"

# packer runs ansible using as hostname the 'default' string
# and caches the facts for that host to /tmp/fact.d/prod/default
# make sure to delete the cached facts, so they don't interfere with this run
rm -f .facts/default

# support packer 1.8
PACKER_VERSION=$(packer --version)
if [[ $(echo $PACKER_VERSION | cut -d'.' -f1) -ge 1 ]] && [[ $(echo $PACKER_VERSION | cut -d'.' -f2) -gt 7 ]]; then
  packer init $LOCAL_PATH/../build/require.pkr.hcl
fi

# Ubuntu 18.04 by default only has python3. ansible_python_interpreter tells ansible to map /usr/bin/python to /usr/bin/python3

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

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
-var "subnet_ocid=$PUBLIC_SUBNET_OCID" \
-var "compartment_ocid=$TENANCY_OCID" \
-var "shape=$SHAPE" \
-var "ocpus=$OCPUS" \
-var "cloud_provider=$CLOUD_PROVIDER" \
-var "memory_in_gbs=$MEMORY_IN_GBS" \
-var "jicofo_deb_pkg_version=$DEB_JICOFO_VERSION" \
-var "jicofo_version=$JICOFO_VERSION" \
-var "jitsi_meet_version=$JITSI_MEET_VERSION" \
-var "prosody_version=$PROSODY_VERSION" \
-var "ansible_python_interpreter=/usr/bin/python3" \
-var "ansible_deploy_tags=$DEPLOY_TAGS" \
-var "ansible_skip_tags=failfast" \
-var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
-var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
-var="tag_namespace=$TAG_NAMESPACE" \
-var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
$LOCAL_PATH/../build/build-jicofo-hotfix-oracle.json
