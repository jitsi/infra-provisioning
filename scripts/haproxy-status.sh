#!/usr/bin/env bash

# haproxy-status.sh
# wrapper for check_haproxy_status.py that checks the current status of stick
# tables and optionally injects stick table fixes 

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

[ -z "$ANSIBLE_BUILD_PATH" ] && ANSIBLE_BUILD_PATH="$LOCAL_PATH/../../infra-configuration"

[ -z "$LOG_PATH" ] && LOG_PATH="/var/log/proxy_monitor/$ENVIRONMENT-stick-table-fixes.json.log"

unset ANSIBLE_SSH_USER
if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: run ansible as $ANSIBLE_SSH_USER"
fi

HAPROXY_STATUS_OUTPUT="$LOCAL_PATH/../../haproxy-status/$ENVIRONMENT"
HAPROXY_STATUS_COMPARE_OLD=${HAPROXY_STATUS_COMPARE_OLD-"false"}

#leave stick table fixes
[ -z "$HAPROXY_STICK_TABLE_FIXES_ENABLED" ] && HAPROXY_STICK_TABLE_FIXES_ENABLED="false"

usage() { echo "Usage: $0 [<username>]" 1>&2; }
#usage

cd $ANSIBLE_BUILD_PATH

#update inventory cache every 2 hours
CACHE_TTL=${HAPROXY_CACHE_TTL-"7200"}

# set HAPROXY_CACHE and build cache if needed
CACHE_TTL=$CACHE_TTL . $LOCAL_PATH/haproxy-buildcache.sh 
if [ $? -ne 0 ]; then
    echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status ERROR: haproxy-buildcache.sh unable to build inventory"
    exit 1
fi

DEPLOY_TAGS=${ANSIBLE_TAGS-"all"}
ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY-"$HAPROXY_CACHE"}
HAPROXY_STATUS_IGNORE_LOCK=${HAPROXY_STATUS_IGNORE_LOCK-"false"}

# clear out existing haproxy status output if exists
if [ -d $HAPROXY_STATUS_OUTPUT ]; then
  if [ "$HAPROXY_STATUS_COMPARE_OLD" == "true" ]; then
      echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: comparing old stick table entries with new"
  else
      echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: checking haproxy status and for split brains"
      rm $HAPROXY_STATUS_OUTPUT/* >/dev/null 2>&1 || true
  fi
else
  echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: creating directory: $HAPROXY_STATUS_OUTPUT"
  mkdir -p $HAPROXY_STATUS_OUTPUT
fi

echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: pulling stick tables from ${ANSIBLE_INVENTORY}"

set -x

ansible-playbook --verbose ansible/haproxy-status.yml --extra-vars "hcv_environment=$ENVIRONMENT" \
-i $ANSIBLE_INVENTORY \
-e "ansible_ssh_user=$ANSIBLE_SSH_USER" \
-e "hcv_haproxy_status_ignore_lock=$HAPROXY_STATUS_IGNORE_LOCK" \
--tags "$DEPLOY_TAGS" > $HAPROXY_STATUS_OUTPUT/ansible.out 2>&1
if [ $? -ne 0 ]; then
    echo "## $(date +%Y-%m-%dT%H:%M:%S) ERROR: haproxy-status.yml run failed"
    exit 2
fi

set +x

if [ "$HAPROXY_STATUS_COMPARE_OLD" == "true" ]; then
  # compare old and new stick tables with no further action
  $LOCAL_PATH/check_haproxy_status.py --environment $ENVIRONMENT --directory $HAPROXY_STATUS_OUTPUT --compare_old true
  if [ $? -ne 0 ]; then
      echo "## $(date +%Y-%m-%dT%H:%M:%S) ERROR: check_haproxy_status.py failed when comparing old with new"
      exit 3
  fi
else
  # process the status and output stats to cloudwatch
  $LOCAL_PATH/check_haproxy_status.py --environment $ENVIRONMENT --directory $HAPROXY_STATUS_OUTPUT
  if [ $? -ne 0 ]; then
      echo "## $(date +%Y-%m-%dT%H:%M:%S) ERROR: check_haproxy_status.py failed when processing status"
      exit 4
  fi
  if [ -e "${HAPROXY_STATUS_OUTPUT}/stick-table-fixes.json" ]; then
      if [ "$HAPROXY_STICK_TABLE_FIXES_ENABLED" == "true" ]; then
          echo "{\"$(date +%Y-%m-%dT%T)\": $(cat "${HAPROXY_STATUS_OUTPUT}/stick-table-fixes.json")}" >> $LOG_PATH
          STICK_TABLE_ENTRIES_FILE=$(realpath "${HAPROXY_STATUS_OUTPUT}/stick-table-fixes.json") $LOCAL_PATH/set-haproxy-stick-table.sh $ANSIBLE_SSH_USER
      else
          echo "## $(date +%Y-%m-%dT%H:%M:%S) WARNING: split brain captured in ${HAPROXY_STATUS_OUTPUT}/stick-table-fixes.json; set HAPROXY_STICK_TABLE_FIXES_ENABLED to true if you want to fix it"
      fi
  else
      echo "## $(date +%Y-%m-%dT%H:%M:%S) haproxy-status: no split brains detected in $ENVIRONMENT"
  fi
fi

cd -