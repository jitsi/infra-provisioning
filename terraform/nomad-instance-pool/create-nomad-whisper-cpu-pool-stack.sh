#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="whisper-cpu"
[ -z "$DISK_IN_GBS" ] && export DISK_IN_GBS="50"
# start with only 1 for whisper CPU pools
[ -z "$INSTANCE_POOL_SIZE" ] && export INSTANCE_POOL_SIZE=1
[ -z "$POSTRUNNER_PATH" ] && export POSTRUNNER_PATH="terraform/nomad-instance-pool/user-data/postinstall-runner-whisper-cpu-oracle.sh"

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
