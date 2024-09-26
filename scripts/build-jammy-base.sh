#!/bin/bash
set -x #echo on
#!/usr/bin/env bash
unset ANSIBLE_SSH_USER

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$REBUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID=$BUILD_ID
[ -z $ANSIBLE_BUILD_ID ] && ANSIBLE_BUILD_ID="standalone"

[ -z $BUILD_TYPE ] && BUILD_TYPE="JammyBase"

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration/ansible"

SUBNET="subnet-00051c7baffa4f59e"
CLOUD_NAME="us-west-2-aws1"
EC2_VPC_ID="vpc-09c9910ebd7469442"
DEFAULT_JAMMY_EC2_IMAGE_ID_AMD64="ami-0ee8244746ec5d6d4"
DEFAULT_JAMMY_EC2_IMAGE_ID_ARM64="ami-076d7bf6ac3493160"


[ -z "$EC2_INSTANCE_TYPE_AMD64" ] && EC2_INSTANCE_TYPE_AMD64="t3.large"
[ -z "$EC2_INSTANCE_TYPE_ARM64" ] && EC2_INSTANCE_TYPE_ARM64="t4g.large"

[ -z $TARGET_ARCHITECTURE ] && TARGET_ARCHITECTURE="x86_64"

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh"

#default defined in region-specific variables sourced above

if [[ "$TARGET_ARCHITECTURE" == "amd64" ]] || [[ "$TARGET_ARCHITECTURE" == "x86_64" ]]; then
  EC2_IMAGE_ID=$DEFAULT_JAMMY_EC2_IMAGE_ID_AMD64
  EC2_INSTANCE_TYPE=$EC2_INSTANCE_TYPE_AMD64
fi

if [[ "$TARGET_ARCHITECTURE" == "arm64" ]] || [[ "$TARGET_ARCHITECTURE" == "aarch64" ]]; then
  EC2_IMAGE_ID=$DEFAULT_JAMMY_EC2_IMAGE_ID_ARM64
  EC2_INSTANCE_TYPE=$EC2_INSTANCE_TYPE_ARM64
fi

if [ -z $EC2_IMAGE_ID ]; then
    echo "No EC2_IMAGE_ID provided or found, and no DEFAULT_JAMMY_EC2_IMAGE_ID defined for region $EC2_REGION.  Exiting..."
    exit 1
fi

#don't set -e until after all variables are set
set -e

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

[ -z "$EC2_VPC_ID" ] && EC2_VPC_ID=$(aws ec2 describe-vpcs --region "$EC2_REGION" --filters Name=isDefault,Values=true| jq -r '.Vpcs[].VpcId')
[ -z "$EC2_VPC_SUBNET" ] && EC2_VPC_SUBNET=$(aws ec2 describe-subnets --region "$EC2_REGION" --filters Name=vpc-id,Values="$EC2_VPC_ID" Name=state,Values=available | jq -r '.Subnets[].SubnetId' | head -n 1)

[ -z "$SUBNET" ] && SUBNET=$EC2_VPC_SUBNET

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

ansible-playbook $ANSIBLE_BUILD_PATH/build-focal-base.yml -i "somehost," \
-e "ec2_build_type=$BUILD_TYPE" \
-e "build_id=$ANSIBLE_BUILD_ID" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-e "ec2_keypair=$EC2_SSH_KEYPAIR" \
-e "ec2_instance_type=$EC2_INSTANCE_TYPE" \
$([ ! -z $EC2_VPC_ID ] && echo "-e ec2_vpc_id=$EC2_VPC_ID") \
$([ ! -z $EC2_REGION ] && echo "-e ec2_region=$EC2_REGION") \
$([ ! -z $SUBNET ] && echo "-e ec2_vpc_subnet_id=$SUBNET") \
$([ ! -z $EC2_IMAGE_ID ] && echo "-e ec2_image_id=$EC2_IMAGE_ID") \
--vault-password-file $ANSIBLE_BUILD_PATH/../.vault-password.txt \
--tags "$DEPLOY_TAGS"
