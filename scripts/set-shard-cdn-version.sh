#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))


if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT specified, exiting"
    exit 2
fi

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi


if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER specified, exiting"
    exit 2
fi


if [ -z "$CDN_VERSION" ]; then
    echo "No CDN_VERSION specified, exiting"
    exit 2
fi

#set -x

PACKAGE_NAME=$(yq eval ".jitsi_meet_branding_override" $LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml|tail -1)
if [[ "$PACKAGE_NAME" == "null" ]]; then
    PACKAGE_NAME=""
fi
CDN_PREFIX=$(yq eval ".jitsi_meet_cdn_prefix" $LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml | tail -1)
if [[ "$CDN_PREFIX" == "null" ]]; then
    CDN_PREFIX=""
fi

CDN_CLOUDFLARE_FLAG=$(yq eval ".jitsi_meet_cdn_cloudflare_enabled" $LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml | tail -1)
if [[ "$CDN_CLOUDFLARE_FLAG" == "null" ]]; then
    CDN_CLOUDFLARE_FLAG="false"
fi

if [[ "$CDN_CLOUDFLARE_FLAG" == "true" ]]; then
    [ -z "$CDN_BASE" ] && CDN_BASE="/v1/_cdn"
else
    [ -z "$CDN_BASE" ] && CDN_BASE="web-cdn.jitsi.net"
fi

[ -z "$PACKAGE_NAME" ] && PACKAGE_NAME="jitsi-meet"

SIGNAL_INVENTORY_PATH="./signal-release-$RELEASE_NUMBER.inventory"

DEST_PATH="/usr/share/$PACKAGE_NAME"
CDN_PATH="$DEST_PATH/base.html"

# build inventory
echo "Building signal node inventory into $SIGNAL_INVENTORY_PATH"
$LOCAL_PATH/node.py --environment $ENVIRONMENT --role core --region all --oracle --release $RELEASE_NUMBER --batch > $SIGNAL_INVENTORY_PATH

BASE_PATH="./base.html"
echo -n "<base href=\"https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/\" />" > $BASE_PATH

wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/libs/external_api.min.js.map
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/libs/external_api.min.js
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/libs/lib-jitsi-meet.min.js
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/libs/lib-jitsi-meet.min.map

wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/static/recommendedBrowsers.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/static/welcomePageAdditionalContent.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/static/accessStorage.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/static/accessStorage.min.js
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/static/accessStorage.min.map

wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/body.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/fonts.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/head.html
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/interface_config.js
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/manifest.json
wget -q https://$CDN_BASE/$CDN_PREFIX$CDN_VERSION/title.html

LIST_FILES_FROM_ROOT_DIR="$BASE_PATH ./body.html ./fonts.html ./head.html ./interface_config.js ./manifest.json ./title.html"

echo "NEW CDN VERSION IS:"
cat $BASE_PATH
for i in `cat $SIGNAL_INVENTORY_PATH`; do
    echo "OLD CDN VERSION on $i"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "cat $CDN_PATH"
    echo "COPYING NEW CDN VERSION TO $i"
    scp -F "$LOCAL_PATH/../config/ssh.config" $LIST_FILES_FROM_ROOT_DIR \
      ./recommendedBrowsers.html \
      ./welcomePageAdditionalContent.html \
      ./external_api.min.js.map \
      ./external_api.min.js \
      ./lib-jitsi-meet.min.js \
      ./lib-jitsi-meet.min.map \
      ./accessStorage.html \
      ./accessStorage.min.js \
      ./accessStorage.min.map \
      $ANSIBLE_SSH_USER@$i:
done

for i in `cat $SIGNAL_INVENTORY_PATH`; do
    echo "APPLYING NEW CDN VERSION on $i"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./base.html $CDN_PATH"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./external_api.min.* $DEST_PATH/libs"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./lib-jitsi-meet.min.* $DEST_PATH/libs"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./recommendedBrowsers.html $DEST_PATH/static"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./welcomePageAdditionalContent.html $DEST_PATH/static"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./accessStorage.html $DEST_PATH/static"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./accessStorage.min.js $DEST_PATH/static"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp ./accessStorage.min.map $DEST_PATH/static"
    ssh -F "$LOCAL_PATH/../config/ssh.config" $ANSIBLE_SSH_USER@$i "sudo cp $LIST_FILES_FROM_ROOT_DIR $DEST_PATH"
done
