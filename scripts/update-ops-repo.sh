#!/bin/bash

set -x

# e.g. scripts
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

# pull in oracle namespace
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . $LOCAL_PATH/../clouds/oracle.sh

[ -z "$OPS_REPO_BUCKET" ] && OPS_REPO_BUCKET="ops-repo"
[ -z "$S3FS_PASSWORD_PATH" ] && S3FS_PASSWORD_PATH="/etc/.passwd-s3fs"
[ -z "$ORACLE_REGION" ] && ORACLE_REGION="us-phoenix-1"
[ -z "$OPS_REPO_MOUNT_PATH" ] && OPS_REPO_MOUNT_PATH="/mnt/ops-repo"

[ ! -d "$OPS_REPO_MOUNT_PATH" ] && sudo mkdir -p "$OPS_REPO_MOUNT_PATH"

[ -z "$REPO_PATH" ] && REPO_PATH="$OPS_REPO_MOUNT_PATH/repo/debian"
[ -z "$REPO_CONF" ] && REPO_CONF="$OPS_REPO_MOUNT_PATH/jitsi-debian-pkg.conf"

sudo /usr/bin/s3fs "$OPS_REPO_MOUNT_PATH" -o "bucket=$OPS_REPO_BUCKET" -o "passwd_file=$S3FS_PASSWORD_PATH" -o "url=https://$ORACLE_S3_NAMESPACE.compat.objectstorage.$ORACLE_REGION.oraclecloud.com" -o nomultipart -o use_path_request_style -o "endpoint=$ORACLE_REGION" -o allow_other -o umask=000

if [ $? -gt 0 ]; then
    echo "Failed to mount bucket, skipping further steps."
    exit 5
fi

if [ -z "$UPSTREAM_CI_SERVER" ]; then
    echo "No upstream CI server specified, not copying any new files"
else
    if [ -z "$FILES_TO_COPY" ]; then
        echo "No FILES_TO_COPY set, not copying any new files"
    else
        scp $UPSTREAM_CI_USER@$UPSTREAM_CI_SERVER:$FILES_TO_COPY $REPO_PATH/mini-dinstall/incoming
        ls -l $REPO_PATH/mini-dinstall/incoming
    fi
fi

mini-dinstall -b -c $REPO_CONF $REPO_PATH

exit $?