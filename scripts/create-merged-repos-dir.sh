#!/bin/bash

[ -z "$LOCAL_DEV_DIR" ] && LOCAL_DEV_DIR="$(realpath "$HOME")"
[ -z "$MERGED_DIR" ] && MERGED_DIR="$HOME/merged"

[ ! -d "$MERGED_DIR" ] && mkdir -p $MERGED_DIR

rsync --exclude '.git/' --exclude '.terraform' -avz $LOCAL_DEV_DIR/infra-provisioning $MERGED_DIR
rsync --exclude '.git/' --exclude '.terraform' -avz $LOCAL_DEV_DIR/infra-configuration $MERGED_DIR

rsync --exclude '.git/' --exclude '.terraform' -avz $LOCAL_DEV_DIR/infra-customizations-private/ $MERGED_DIR/infra-provisioning
rsync --exclude '.git/' --exclude '.terraform' -avz $LOCAL_DEV_DIR/infra-customizations-private/ $MERGED_DIR/infra-configuration

cd $MERGED_DIR

if [ -n "$1" ]; then
    exec $1
fi
