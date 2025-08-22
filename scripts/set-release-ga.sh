#!/bin/bash

echo "## starting set-release-ga.sh"

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
  echo "## set-release-ga: ansible SSH user is not defined. We use current user: $ANSIBLE_SSH_USER"
else
  ANSIBLE_SSH_USER=$1
  echo "## set-release-ga: run ansible as $ANSIBLE_SSH_USER"
fi

if [ -z "$RELEASE_NUMBER" ]; then
  echo "## ERROR in set-release-ga: RELEASE_NUMBER must be set"
  exit 40
fi

echo "## set-release-ga: setting new live release in consul"
CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" RELEASE_NUMBER=$RELEASE_NUMBER scripts/consul-set-release-ga.sh $ANSIBLE_SSH_USER
RET=$?
if [ $RET -gt 0 ]; then
  echo -e "## set-release-ga: ERROR return code from consul-set-release-ga: $RET"
  exit 60
fi

exit 0