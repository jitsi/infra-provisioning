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

[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="$SIGNAL_BASE_IMAGE_TYPE"
[ -z "$BASE_IMAGE_TYPE" ] && BASE_IMAGE_TYPE="NobleBase"

arch_from_shape $SHAPE

[ -z "$BASE_IMAGE_ID" ] && BASE_IMAGE_ID=$($LOCAL_PATH/oracle_custom_images.py --architecture "$IMAGE_ARCH" --type $BASE_IMAGE_TYPE --region="$ORACLE_REGION" --compartment_id="$COMPARTMENT_OCID" --tag_namespace="$TAG_NAMESPACE")

if [ -z "$JICOFO_VERSION" ]; then
    JICOFO_VERSION='latest'
    DEB_JICOFO_VERSION='*'
else
    DEB_JICOFO_VERSION="$JICOFO_VERSION"
    [ "$DEB_JICOFO_VERSION" == "*" ] || echo $DEB_JICOFO_VERSION | grep -q "1\.0" || DEB_JICOFO_VERSION="1.0-${DEB_JICOFO_VERSION}-1"
    [ "$DEB_JICOFO_VERSION" == "*" ] || echo $DEB_JICOFO_VERSION | grep -q -- -1$ || DEB_JICOFO_VERSION="${DEB_JICOFO_VERSION}-1"
fi

if [ -z "$JITSI_MEET_VERSION" ]; then
    JITSI_MEET_VERSION="latest"
    DEB_JITSI_MEET_VERSION='*'
else
    DEB_JITSI_MEET_VERSION="$JITSI_MEET_VERSION"
    [ "$DEB_JITSI_MEET_VERSION" == "*" ] || echo $DEB_JITSI_MEET_VERSION | grep -q "1\.0" || DEB_JITSI_MEET_VERSION="1.0.${DEB_JITSI_MEET_VERSION}-1"
    [ "$DEB_JITSI_MEET_VERSION" == "*" ] || echo $DEB_JITSI_MEET_VERSION | grep -q -- -1$ || DEB_JITSI_MEET_VERSION="${DEB_JITSI_MEET_VERSION}-1"
fi

if [ -z "$JITSI_MEET_META_VERSION" ]; then
    JITSI_MEET_META_VERSION='*'
fi

# clear prosody version if 'latest' is requested
if [[ "$PROSODY_VERSION" == "latest" ]]; then
  PROSODY_VERSION=
fi

PROSODY_APT_FLAG=''
PROSODY_VERSION_FLAG='{}'
if [ -n "$PROSODY_FROM_URL" ]; then
    # Explicit PROSODY_FROM_URL flag takes precedence
    if [ "$PROSODY_FROM_URL" == "true" ]; then
      PROSODY_APT_FLAG="false"
      if [ -n "$PROSODY_VERSION" ]; then
        PROSODY_URL_VERSION="$PROSODY_VERSION"
        PROSODY_VERSION_FLAG="{\"prosody_url_version\":\"$PROSODY_URL_VERSION\"}"
      fi
    fi
    [ "$PROSODY_FROM_URL" == "false" ] && PROSODY_APT_FLAG="true"
    PROSODY_APT_FLAG="{\"prosody_install_from_apt\":$PROSODY_APT_FLAG}"
elif [ -n "$PROSODY_VERSION" ]; then
    # PROSODY_VERSION specified without PROSODY_FROM_URL: install from URL
    PROSODY_APT_FLAG="{\"prosody_install_from_apt\":false}"
    PROSODY_URL_VERSION="$PROSODY_VERSION"
    PROSODY_VERSION_FLAG="{\"prosody_url_version\":\"$PROSODY_URL_VERSION\"}"
fi
# If neither PROSODY_FROM_URL nor PROSODY_VERSION is specified, use ansible defaults

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

ORACLE_SIGNAL_IMAGE_LIMIT=20
# clean custom signal images if limit is exceeded (may fail, but that's OK)
for CLEAN_ORACLE_REGION in $ORACLE_IMAGE_REGIONS; do
  echo "Cleaning images in $CLEAN_ORACLE_REGION"
  $LOCAL_PATH/oracle_custom_images.py --clean $ORACLE_SIGNAL_IMAGE_LIMIT --architecture "$IMAGE_ARCH" --delete --region=$CLEAN_ORACLE_REGION --type=Signal --compartment_id=$TENANCY_OCID;
done

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
-var "jitsi_meet_deb_pkg_version=$DEB_JITSI_MEET_VERSION" \
-var "jicofo_version=$JICOFO_VERSION" \
-var "jitsi_meet_version=$JITSI_MEET_VERSION" \
-var "prosody_version=$PROSODY_VERSION" \
$([ ! -z $PROSODY_APT_FLAG ] && echo "-var prosody_apt_flag=$PROSODY_APT_FLAG") \
$([ ! -z $PROSODY_PACKAGE_VERSION ] && echo "-var prosody_package_version=$PROSODY_PACKAGE_VERSION") \
$([ ! -z $PROSODY_URL_VERSION ] && echo "-var prosody_version_flag=$PROSODY_VERSION_FLAG") \
-var "ansible_python_interpreter=/usr/bin/python3" \
-var "ansible_deploy_tags=$DEPLOY_TAGS" \
-var "ansible_skip_tags=failfast" \
-var "infra_configuration_repo=$INFRA_CONFIGURATION_REPO" \
-var "infra_customizations_repo=$INFRA_CUSTOMIZATIONS_REPO" \
-var="tag_namespace=$TAG_NAMESPACE" \
-var "connection_use_private_ip=$CONNECTION_USE_PRIVATE_IP" \
$LOCAL_PATH/../build/build-signal-oracle.json
