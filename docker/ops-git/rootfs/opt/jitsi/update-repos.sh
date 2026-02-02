#!/bin/bash

REPOS="infra-provisioning.git infra-configuration.git infra-customizations-private.git jitsi-meet.git jitsi-meet-torture.git"

UPDATE_DIR="/tmp/update"

export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
eval "$(ssh-agent -s)"
trap "kill $SSH_AGENT_PID" exit

function mirrorrepo {
  REPO=$1
  # first do a git pull in the local repo
  cd /home/git/jitsi/$REPO
  git pull

  # now do a mirror clone in the update dir
  cd $UPDATE_DIR
  /usr/bin/git clone --mirror git@github.com:jitsi/$REPO

  cd $REPO
  # move into the newly cloned repo and set the push url to the local git server
  git remote set-url --push origin git@localhost:jitsi/$REPO
  git fetch -p origin
  # mirror the repo to the local git server
  git push --mirror
}

ssh-add ~/.ssh/id_rsa
set -x

# make sure we have a clean update dir
mkdir -p $UPDATE_DIR

#subshell to avoid having to cd back
(
    # mirror each repo
    for REPO in $REPOS; do
        mirrorrepo $REPO
    done
)

rm -rf $UPDATE_DIR