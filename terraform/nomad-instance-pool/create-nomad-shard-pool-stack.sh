#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="shard"
[ -z "$DISK_IN_GBS" ] && DISK_IN_GBS="50"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
