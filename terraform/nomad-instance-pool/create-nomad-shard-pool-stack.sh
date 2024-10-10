#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="shard"
[ -z "$DISK_IN_GBS" ] && export DISK_IN_GBS="50"
# at least 2 for shard pools
[ -z "$INSTANCE_POOL_SIZE" ] && export INSTANCE_POOL_SIZE=2

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
