#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="x86"
[ -z "$SHAPE" ] && export SHAPE="VM.Standard.E5.Flex"
[ -z "$DISK_IN_GBS" ] && export DISK_IN_GBS="50"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
