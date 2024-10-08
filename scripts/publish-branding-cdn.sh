#!/bin/bash

# publish_meet_cdn.sh

set -x
set -e

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

CONFIG_VARS_PATH="$LOCAL_PATH/../config/vars.yml"


[ -z "$JITSI_MEET_VERSION" ] && JITSI_MEET_VERSION="$1"
[ -z "$BRANDING_VERSION" ] && JITSI_MEET_VERSION="$2"
[ -z "$BRANDING_NAME" ] && BRANDING_NAME="$3"

if [ -z "$JITSI_MEET_VERSION" ]; then
    echo "No JITSI_MEET_VERSION specified, exiting..."
    exit 1
fi

if [ -z "$BRANDING_VERSION" ]; then
    echo "No BRANDING_VERSION specified, exiting..."
    exit 1
fi

[ -z "$CDN_S3_BUCKET" ] && CDN_S3_BUCKET="$(yq '.cdn_s3_bucket' < $CONFIG_VARS_PATH)"

[ -z "$CDN_R2_BUCKET" ] && CDN_R2_BUCKET="$(yq '.cdn_r2_bucket' < $CONFIG_VARS_PATH)"

if [ -n "$CDN_R2_BUCKET" ]; then
    R2_SECRETS_PATH="$LOCAL_PATH/../ansible/secrets/r2-bucket.yml"
    [ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"
    set +x
    R2_ACCESS_KEY_ID="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_access_key_id" -)"
    R2_SECRET_ACCESS_KEY="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_secret_access_key" -)"
    R2_ENDPOINT_URL="$(ansible-vault view $R2_SECRETS_PATH --vault-password $VAULT_PASSWORD_FILE | yq eval ".r2_endpoint_url" -)"
    set -x
fi

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

BRANDING_COMPLETE_VERSION="${JITSI_MEET_VERSION}.${BRANDING_VERSION}"

#build up full version for debian filename
BRANDING_FULL_VERSION="1.0.${BRANDING_COMPLETE_VERSION}-1"

#now do the branding
VERSION_PREFIX=`echo "${BRANDING_NAME}_" | sed -r 's/-+//g'`
DEB_FILENAME="${BRANDING_NAME}_${BRANDING_FULL_VERSION}_all.deb"
DEB_URL="$REPO_URL/$DEB_FILENAME"

#temp folder to extract to
DEB_PATH="./publish_branding_cdn/$BRANDING_COMPLETE_VERSION"

#clear existing directory
[ -e "$DEB_PATH" ] && rm -rf $DEB_PATH/*
[ ! -e "$DEB_PATH" ] && mkdir -p $DEB_PATH

pushd $DEB_PATH

curl -O $DEB_URL

dpkg -x $DEB_FILENAME .

if [ -n "$CDN_R2_BUCKET" ]; then
    AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY \
    AWS_DEFAULT_REGION=auto \
    aws s3 cp --recursive usr/share/${BRANDING_NAME} s3://$CDN_R2_BUCKET/v1/_cdn/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/ \
    --endpoint-url $R2_ENDPOINT_URL &
fi

aws s3 cp --recursive usr/share/${BRANDING_NAME} s3://$CDN_S3_BUCKET/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/ &

wait

s3cmd --recursive modify --add-header="Cache-Control: public, max-age=31536000" s3://$CDN_S3_BUCKET/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/
s3cmd --recursive modify --add-header="Access-Control-Allow-Origin: *" s3://$CDN_S3_BUCKET/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/
s3cmd --recursive modify --add-header="Cross-Origin-Resource-Policy: cross-origin" s3://$CDN_S3_BUCKET/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/
# Default mime type mapping doesn't identify wasm files correctly
s3cmd --recursive modify --exclude='*' --include='*.wasm' --add-header="Content-Type: application/wasm" s3://$CDN_S3_BUCKET/${VERSION_PREFIX}${BRANDING_COMPLETE_VERSION}/

popd

rm -rf $DEB_PATH
