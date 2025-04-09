#!/bin/bash
set -x #echo on
set -e
#!/usr/bin/env bash
unset ANSIBLE_SSH_USER

[ -z "$BUILD_ID" ] && BUILD_ID="standalone"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration/ansible"

#use the latest build of JVB deb by default
if [ -z "$JVB_VERSION" ]; then
    JVB_VERSION='*'
else
    [ "$JVB_VERSION" == "*" ] || echo $JVB_VERSION | grep -q -- -1$ || JVB_VERSION="${JVB_VERSION}-1"
fi

if [ -z "$JITSI_MEET_META_VERSION" ]; then
    JITSI_MEET_META_VERSION='*'
fi


#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

ORACLE_CLOUD_NAME="$ORACLE_REGION-$ENVIRONMENT-oracle"
[ -e "$LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${ORACLE_CLOUD_NAME}.sh

[ -z "$IMAGE_ARCH" ] && IMAGE_ARCH="aarch64"

if [[ "$IMAGE_ARCH" == "aarch64" ]]; then
  [ -z "$SHAPE" ] && SHAPE="$SHAPE_A_1"  
fi

[ -z "$SHAPE" ] && SHAPE="$SHAPE_E_6"
[ -z "$OCPUS" ] && OCPUS="4"
[ -z "$MEMORY_IN_GBS" ] && MEMORY_IN_GBS="12"

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$JVB_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="JammyBase"

arch_from_shape $SHAPE

[ -z "$BASE_IMAGE_ID" ] && BASE_IMAGE_ID=$($LOCAL_PATH/oracle_custom_images.py --type $BASE_IMAGE_TYPE --architecture "$IMAGE_ARCH" --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")
# bionic uses python
#SYSTEM_PYTHON="/usr/bin/python"

# focal uses python3
SYSTEM_PYTHON="/usr/bin/python3"

# addtional bastion configs
[ -z "$CONNECTION_SSH_PRIVATE_KEY_FILE" ] && CONNECTION_SSH_PRIVATE_KEY_FILE="~/.ssh/id_ed25519"

# run as user
if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

# clean custom JVB images if limit is exceeded (may fail, but that's OK)
set +e
for CLEAN_ORACLE_REGION in $ORACLE_IMAGE_REGIONS; do
  echo "Cleaning images in $CLEAN_ORACLE_REGION"
  $LOCAL_PATH/oracle_custom_images.py --clean $ORACLE_CUSTOM_IMAGE_LIMIT --architecture "$IMAGE_ARCH" --delete --region=$CLEAN_ORACLE_REGION --type=JVB --compartment_id=$TENANCY_OCID;
done
set -e

# packer runs ansible using as hostname the 'default' string
# and caches the facts for that host to /tmp/fact.d/prod/default
# make sure to delete the cached facts, so they don't interfere with this run
rm -f .facts/default

# support packer 1.8
PACKER_VERSION=$(packer --version)
echo $PACKER_VERSION | grep -q 'Packer' && PACKER_VERSION=$(echo $PACKER_VERSION | cut -d' ' -f2 | cut -d 'v' -f2)
if [[ $(echo $PACKER_VERSION | cut -d'.' -f1) -ge 1 ]] && [[ $(echo $PACKER_VERSION | cut -d'.' -f2) -gt 7 ]]; then
  packer init $LOCAL_PATH/../build/require.pkr.hcl
fi

# Ubuntu 18.04 by default only has python3. ansible_python_interpreter tells ansible to map /usr/bin/python to /usr/bin/python3

packer build \
-var "build_id=$BUILD_ID" \
-var "environment=$ENVIRONMENT" \
-var "ansible_build_path=$ANSIBLE_BUILD_PATH" \
-var "jitsi_videobridge_deb_pkg_version=$JVB_VERSION" \
-var "jitsi_meet_meta_version=$JITSI_MEET_META_VERSION" \
-var "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-var "image_architecture=$IMAGE_ARCH" \
-var "base_image_type=$BASE_IMAGE_TYPE" \
-var "base_image_ocid=$BASE_IMAGE_ID" \
-var "region=$ORACLE_REGION" \
-var "availability_domain=$AVAILABILITY_DOMAIN" \
-var "subnet_ocid=$JVB_SUBNET_OCID" \
-var "compartment_ocid=$TENANCY_OCID" \
-var "shape=$SHAPE" \
-var "ocpus=$OCPUS" \
-var "memory_in_gbs=$MEMORY_IN_GBS" \
-var "ansible_python_interpreter=$SYSTEM_PYTHON" \
-var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
-var "tag_namespace=$TAG_NAMESPACE" \
$LOCAL_PATH/../build/build-jvb-oracle.json
