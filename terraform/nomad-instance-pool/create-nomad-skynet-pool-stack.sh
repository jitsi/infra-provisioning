#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="skynet"
[ -z "$ROLE" ] && export ROLE="skynet"
[ -z "$MEMORY_IN_GBS" ] && export MEMORY_IN_GBS="240"
[ -z "$SHAPE" ] && export SHAPE="VM.GPU.A10.1"
[ -z "$OCPUS" ] && export OCPUS="15"
[ -z "$BASE_IMAGE_TYPE" ] && export BASE_IMAGE_TYPE="GPU"
[ -z "$POSTRUNNER_PATH" ] && export POSTRUNNER_PATH="terraform/nomad-instance-pool/user-data/postinstall-runner-gpu-oracle.sh"
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
