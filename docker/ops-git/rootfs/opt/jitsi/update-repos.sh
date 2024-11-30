#!/bin/bash
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
eval "$(ssh-agent -s)"
trap "kill $SSH_AGENT_PID" exit

ssh-add ~/.ssh/id_rsa
set -x
UPDATE_DIR="/tmp/update"


cd /home/git/jitsi/infra-configuration.git
git pull

cd /home/git/jitsi/infra-provisioning.git
git pull

cd /home/git/jitsi/infra-customizations-private.git
git pull

cd /home/git/jitsi/jitsi-meet.git
git pull

mkdir -p $UPDATE_DIR
cd $UPDATE_DIR

/usr/bin/git clone --mirror git@github.com:jitsi/infra-configuration.git
cd infra-configuration.git
git remote set-url --push origin git@localhost:jitsi/infra-configuration.git
git fetch -p origin
git push --mirror
cd ..

/usr/bin/git clone --mirror git@github.com:jitsi/infra-provisioning.git
cd infra-provisioning.git
git remote set-url --push origin git@localhost:jitsi/infra-provisioning.git
git fetch -p origin
git push --mirror
cd ..

/usr/bin/git clone --mirror git@github.com:jitsi/infra-customizations-private.git
cd infra-customizations-private.git
git remote set-url --push origin git@localhost:jitsi/infra-customizations-private.git
git fetch -p origin
git push --mirror
cd ..

/usr/bin/git clone --mirror git@github.com:jitsi/jitsi-meet.git
cd jitsi-meet.git
git remote set-url --push origin git@localhost:jitsi/jitsi-meet.git
git fetch -p origin
git push --mirror
cd ..
rm -rf $UPDATE_DIR