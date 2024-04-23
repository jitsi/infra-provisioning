#!/bin/bash

ENVIRONMENT=$1
HAPROXY_RELEASE_NUMBER=$2
GIT_BRANCH=$3

if [  -z "$4" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$4
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="aws"

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

if [ ! -d "$ANSIBLE_BUILD_PATH" ]; then
  echo "ANSIBLE_BUILD_PATH $ANSIBLE_BUILD_PATH expected to exist, exiting..."
  exit 202
fi

if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
  . $LOCAL_PATH/../regions/all.sh

  for R in $ALL_REGIONS; do
      echo $R
      PROXY_INSTANCES=$($LOCAL_PATH/node.py --environment $ENVIRONMENT --region $R --role haproxy --batch --id)
      if [ ! -z "$PROXY_INSTANCES" ]; then
          aws ec2 create-tags --region $R --resources $PROXY_INSTANCES --tags Key=git_branch,Value=$GIT_BRANCH Key=haproxy_release_number,Value=$HAPROXY_RELEASE_NUMBER
      fi
  done
fi
if [[ "$CLOUD_PROVIDER" == "oracle" ]]; then
  $LOCAL_PATH/tag_haproxy.py $ENVIRONMENT $HAPROXY_RELEASE_NUMBER $GIT_BRANCH
fi

cd $ANSIBLE_BUILD_PATH
# defaults to update inventory cache every 2 hours
CACHE_TTL=${HAPROXY_CACHE_TTL-"1440"}

## TODO: bring back
#SKIP_BUILD_CACHE=${HAPROXY_IGNORE_CACHE-"false"}

# set HAPROXY_CACHE and build cache if needed
#SKIP_BUILD_CACHE=$SKIP_BUILD_CACHE CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh

#ansible-playbook  -i "$HAPROXY_CACHE" ansible/clear-cloud-cache.yml -e "ansible_ssh_user=$ANSIBLE_SSH_USER"
#cd -