#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

# We need an envirnment "all"
if [ -z "$ENVIRONMENT" ]; then
  echo "No Environment provided or found. Exiting .."
  exit 202
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 203
fi

if [ -z "$SEARCH_STRING" ]; then
  echo "No SEARCH_STRING found. This can be set the name of the meeting or the recording. Exiting..."
  exit 203
fi

[ -z "$SSH_USER" ] && SSH_USER="ubuntu"

RESULT=""

INSTANCES="$($LOCAL_PATH/node.py --role java-jibri --environment $ENVIRONMENT --region $ORACLE_REGION --oracle --batch)"

for INSTANCE_PRIMARY_PRIVATE_IP in $INSTANCES; do

  LOG_RESULT=$(ssh -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP "grep -r /var/log/jitsi/jibri/ -e \"$SEARCH_STRING\"")
  if [ ! -z "$LOG_RESULT" ]; then
    echo "Found log result in instance with ip $INSTANCE_PRIMARY_PRIVATE_IP "
    RESULT="$RESULT $INSTANCE_PRIMARY_PRIVATE_IP"
  fi
done

echo "This command, ssh -o StrictHostKeyChecking=no -F $LOCAL_PATH/../config/ssh.config $SSH_USER@$INSTANCE_PRIMARY_PRIVATE_IP \"grep -r /var/log/jitsi/jibri/ -e \"$SEARCH_STRING\"\", was run on the jibri instances in $ENVIRONMENT region $ORACLE_REGION"
echo "Found the following instances having the searched string: $RESULT"

