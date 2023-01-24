#/bin/bash

# publish-meet-cdn.sh

set -x
set -e

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

CONFIG_VARS_PATH="$LOCAL_PATH/../config/vars.yml"

[ -z "$JITSI_MEET_VERSION" ] && JITSI_MEET_VERSION="$1"

if [ -z "$JITSI_MEET_VERSION" ]; then
    echo "No JITSI_MEET_VERSION specified, exiting..."
    exit 1
fi

[ -z "$CDN_S3_BUCKET" ] && CDN_S3_BUCKET="$(yq '.cdn_s3_bucket' < $CONFIG_VARS_PATH)"

if [ -z "$REPO_URL" ]; then
    REPO_SECRETS_PATH="$LOCAL_PATH/../ansible/secrets/repo.yml"
    [ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

    set +x
    REPO_HOST="$(ansible-vault view $REPO_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".jitsi_repo_host" -)"
    REPO_USER="$(ansible-vault view $REPO_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".jitsi_repo_username" -)"
    REPO_PASSWORD="$(ansible-vault view $REPO_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".jitsi_repo_password" -)"
    REPO_URL="https://${REPO_USER}:${REPO_PASSWORD}@${REPO_HOST}/debian/unstable"
    set -x
fi


#make sure JITSI_MEET_VERSION is the short version
echo $JITSI_MEET_VERSION | grep -q "1\.0" && JITSI_MEET_VERSION=$(echo $JITSI_MEET_VERSION | cut -d'.' -f3 | cut -d'-' -f1)

#build up full version for debian filename
JITSI_MEET_FULL_VERSION="1.0.${JITSI_MEET_VERSION}-1"

DEB_FILENAME="jitsi-meet-web_${JITSI_MEET_FULL_VERSION}_all.deb"
DEB_URL="$REPO_URL/$DEB_FILENAME"

#temp folder to extract to
DEB_PATH="./publish_meet_cdn/$JITSI_MEET_VERSION"

#clear existing directory
[ -e "$DEB_PATH" ] && rm -rf $DEB_PATH/*
[ ! -e "$DEB_PATH" ] && mkdir -p $DEB_PATH

echo "Changing directory to $DEB_PATH"
pushd $DEB_PATH

curl -O $DEB_URL

dpkg -x $DEB_FILENAME .

aws s3 cp --recursive usr/share/jitsi-meet s3://$CDN_S3_BUCKET/$JITSI_MEET_VERSION/
s3cmd --recursive modify --add-header="Cache-Control: public, max-age=31536000" s3://$CDN_S3_BUCKET/$JITSI_MEET_VERSION/
s3cmd --recursive modify --add-header="Access-Control-Allow-Origin: *" s3://$CDN_S3_BUCKET/$JITSI_MEET_VERSION/
s3cmd --recursive modify --add-header="Cross-Origin-Resource-Policy: cross-origin" s3://$CDN_S3_BUCKET/$JITSI_MEET_VERSION/
# Default mime type mapping doesn't identify wasm files correctly
s3cmd --recursive modify --exclude='*' --include='*.wasm' --add-header="Content-Type: application/wasm" s3://$CDN_S3_BUCKET/$JITSI_MEET_VERSION/

echo "Changing back from $DEB_PATH"
popd

rm -rf $DEB_PATH

echo "Exiting cleanly from CDN publish"

exit 0
