#!/bin/bash
set -x #echo on
set -e

#!/usr/bin/env bash
unset ANSIBLE_SSH_USER

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$REBUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$BUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID="standalone"

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration/ansible"

if [ ! -d "$ANSIBLE_BUILD_PATH" ]; then
  echo "ANSIBLE_BUILD_PATH $ANSIBLE_BUILD_PATH expected to exist, exiting..."
  exit 202
fi

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh

[ -z "$EC2_INSTANCE_TYPE_AMD64" ] && EC2_INSTANCE_TYPE_AMD64="t3.large"
[ -z "$EC2_INSTANCE_TYPE_ARM64" ] && EC2_INSTANCE_TYPE_ARM64="t4g.large"

[ -z $TARGET_ARCHITECTURE ] && TARGET_ARCHITECTURE="x86_64"

if [[ "$TARGET_ARCHITECTURE" == "amd64" ]] || [[ "$TARGET_ARCHITECTURE" == "x86_64" ]]; then
  EC2_INSTANCE_TYPE=$EC2_INSTANCE_TYPE_AMD64
  TARGET_ARCHITECTURE="x86_64"
fi

if [[ "$TARGET_ARCHITECTURE" == "arm64" ]] || [[ "$TARGET_ARCHITECTURE" == "aarch64" ]]; then
  EC2_INSTANCE_TYPE=$EC2_INSTANCE_TYPE_ARM64
  TARGET_ARCHITECTURE="arm64"
fi

[ -z $BASE_IMAGE_ID ] && BASE_IMAGE_ID=$($LOCAL_PATH/ami.py --type JammyBase --batch --region="$EC2_REGION" --architecture="$TARGET_ARCHITECTURE")
[ -z $BASE_IMAGE_ID ] && BASE_IMAGE_ID=$DEFAULT_EC2_IMAGE_ID

if [ -z $BASE_IMAGE_ID ]; then
  echo "No BASE_IMAGE_ID provided or found, and no DEFAULT_EC2_IMAGE_ID defined for region $EC2_REGION.  Exiting..."
fi

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

if [  -z "$2" ]
then
  EC2_SSH_KEYPAIR=video
  echo "Ansible SSH keypair is not defined. We use default keypair: $ANSIBLE_SSH_USER"
else
  EC2_SSH_KEYPAIR=$2
  echo "Building nodes with SSH keypair $EC2_SSH_KEYPAIR"
fi

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}


ansible-playbook $ANSIBLE_BUILD_PATH/build-selenium-grid.yml -v -i "somehost," \
-e "build_id=$ANSIBLE_BUILD_ID" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-e "ec2_keypair=$EC2_SSH_KEYPAIR" \
-e "xenial_ec2_image_id=$BASE_IMAGE_ID" \
-e "ec2_instance_type=$EC2_INSTANCE_TYPE" \
$([ ! -z $EC2_VPC_ID ] && echo "-e ec2_vpc_id=$EC2_VPC_ID") \
$([ ! -z $EC2_REGION ] && echo "-e ec2_region=$EC2_REGION") \
$([ ! -z $EC2_VPC_SUBNET ] && echo "-e ec2_vpc_subnet_id=$EC2_VPC_SUBNET") \
--vault-password-file $ANSIBLE_BUILD_PATH/../.vault-password.txt \
--tags "$DEPLOY_TAGS"
