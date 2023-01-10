#!/usr/bin/env bash
unset ANSIBLE_SSH_USER
set -x #echo on

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "Run ansible as $ANSIBLE_SSH_USER"
fi

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))
[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#load cloud defaults
[ -e $LOCAL_PATH/../regions/all.sh ] && . $LOCAL_PATH/../regions/all.sh

#default cloud if not set
[ -z $CLOUD_NAME ] && CLOUD_NAME=$DEFAULT_CLOUD

#pull in cloud-specific variables
[ -e "$LOCAL_PATH/../clouds/${CLOUD_NAME}.sh" ] && . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh


CMD_SHARD_NUMBER=$(echo $0 | cut -d'-' -f3 | cut -d'.' -f1)

[ -z $TEST_DURATION ] && TEST_DURATION=10

[ -z $SHARD_NUMBER ] && SHARD_NUMBER=$CMD_SHARD_NUMBER

[ -z $TORTURE_COUNT ] && TORTURE_COUNT=1

[ -z $SHARD ] && SHARD="${SHARD_BASE}-${REGION_ALIAS}${JVB_AZ_LETTER}-s${SHARD_NUMBER}"

[ -z $TEST_DOMAIN ] && TEST_DOMAIN=$DOMAIN

[ -z $TORTURE_LONG ] && TORTURE_LONG='all'

[ -z $TEST_ID ] && TEST_ID='standalone'

#jenkins build number, we get it from jenkins
[ -z $BUILD_NUMBER ] && BUILD_NUMBER='N/A'

SHARD_IP=$(IP_TYPE="external" SHARD="$SHARD" $LOCAL_PATH/shard.sh shard_ip $ANSIBLE_SSH_USER)

if [ -z $SHARD_IP ]; then
    echo "No shard IP found, failing to run tests."
    exit 1
fi

#https://web-cdn.jitsi.net/meet8x8com_4570.1272/
#https://web-cdn.jitsi.net/meetjitsi_4628.1277/
#https://web-cdn.jitsi.net/4679/
#set -x
# Extracts the jitsi-meet-web version used from the base.html file on the shard.
# Thew results can be:
# - https://web-cdn.jitsi.net/meet8x8com_4570.1272/ for 8x8 deployments
# - https://web-cdn.jitsi.net/meetjitsi_4628.1277/ for meet.jit.si
# - https://web-cdn.jitsi.net/4679/ for those without branding as beta.meet.jit.si
#
# with jitsi-meet-web version we check all available meta packages from the newest
# to the latest for that web version and when we find that one
# we use the meta version to construct the tag to use for jitsi-meet-torture
function getJitsiMeetTortureTag() {
  SERVER_IP=$1
  BASE_HTML=$(curl --silent --insecure https://${SERVER_IP}/base.html)
  WEB_FULL_VER=$(echo $BASE_HTML | sed 's|.*web-cdn.jitsi.net/||' | sed 's|/".*||')
  WEB_VER=$(echo $WEB_FULL_VER | sed 's|.*_|| ' | sed 's|\..*||')

  JITSI_MEET_VERSIONS=$(apt-cache madison jitsi-meet | awk '{print $3;}' | cut -d'-' -f1,2,3)
  for item in $JITSI_MEET_VERSIONS
  do
      current_ver=$(apt-cache show jitsi-meet=$item | grep '^Depends:'  | cut -f2- -d: | cut -f2 -d,)
      if grep -q ".${WEB_VER}-1" <<< "$current_ver"; then
          #jitsi-meet-web version ${WEB_VER} is in jitsi-meet (meta) $item
          BUILD_NUM=$(echo $item | sed -n "s/[0-9]*\.[0-9]*\.\([0-9]*\)-1/\1/p")
          #"The tag is jitsi-meet_${BUILD_NUM}"
          echo "jitsi-meet_${BUILD_NUM}";
    break
      fi
  done

  [ -z "$BUILD_NUM" ] && echo "master";
}

if [ -z $TORTURE_BRANCH ]; then
  TORTURE_BRANCH=$(getJitsiMeetTortureTag $SHARD_IP)
fi

[ -z $TORTURE_BRANCH ] && TORTURE_BRANCH="master"

[ -z "$TORTURE_PATH" ] && TORTURE_PATH="../test-results/$TEST_ID"

[ -d "$TORTURE_PATH" ] || mkdir -p $TORTURE_PATH

#clean up results from any previous tests
rm -rf $TORTURE_PATH/*

usage() { echo "Usage: $0 [<username>]" 1>&2; }

usage

if [  -z "$2" ]
then
  EC2_SSH_KEYPAIR=betadeploy
  echo "Ansible SSH keypair is not defined. We use default keypair: $EC2_SSH_KEYPAIR"
else
  EC2_SSH_KEYPAIR=$2
  echo "Building nodes with SSH keypair $EC2_SSH_KEYPAIR"
fi

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}

#first we set the shard state to "testing"
$LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD testing $BUILD_NUMBER

cd $ANSIBLE_BUILD_PATH

ansible-playbook --verbose ansible/torturetest-shard-locally.yml \
-i 'somehost,' \
--extra-vars "hcv_environment=$ENVIRONMENT hcv_domain=$TEST_DOMAIN prosody_domain_name=$TEST_DOMAIN shard_name=$SHARD shard_ip_address=$SHARD_IP torture_longtest_duration=$TEST_DURATION ec2_torture_instance_count=$TORTURE_COUNT torture_longtest_only=$TORTURE_LONG" \
-e "jitsi_torture_git_branch="$TORTURE_BRANCH"" \
-e "test_id=$TEST_ID" \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-e "ec2_keypair=$EC2_SSH_KEYPAIR" \
-e "ec2_torture_image_id=$TORTURE_IMAGE_ID" \
-e "infra_path=$(realpath $LOCAL_PATH/../../..)" \
--vault-password-file .vault-password.txt \
--tags "$DEPLOY_TAGS"

if [ $? -eq 0 ]; then
  #successful run, so keep testing
  TORTURE_LOG_PATH="$TORTURE_PATH/torture_test.log"

  ls $TORTURE_LOG_PATH >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    grep -q "BUILD FAILURE" $TORTURE_LOG_PATH
    if [ $? -eq 0 ]; then
      $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD failed $BUILD_NUMBER
      echo "Torture test \"$TORTURE_LONG\" failed."
      exit 1
    fi
    #success, so mark the shard as tested
      echo "Torture test \"$TORTURE_LONG\" passed."
    $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD passed $BUILD_NUMBER
  else
    $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD failed $BUILD_NUMBER
    echo "Torture test \"$TORTURE_LONG\" no log available."
    exit 2
  fi

else
  $LOCAL_PATH/set_shard_tested.py $ENVIRONMENT $SHARD failed $BUILD_NUMBER
  echo "Torture test ansible run failed."
  exit 1
fi

