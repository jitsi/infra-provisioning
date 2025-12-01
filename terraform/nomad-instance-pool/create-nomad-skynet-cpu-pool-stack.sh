#!/usr/bin/env bash
set -x
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="skynet-cpu"
[ -z "$ROLE" ] && export ROLE="skynet-cpu"
[ -z "$MEMORY_IN_GBS" ] && export MEMORY_IN_GBS="8"
[ -z "$SHAPE" ] && export SHAPE="VM.Standard.E5.Flex"
[ -z "$OCPUS" ] && export OCPUS="4"
[ -z "$BASE_IMAGE_TYPE" ] && export BASE_IMAGE_TYPE="NobleBase"
[ -z "$POSTRUNNER_PATH" ] && export POSTRUNNER_PATH="terraform/nomad-instance-pool/user-data/postinstall-runner-skynet-cpu-oracle.sh"
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-instance-pool-stack.sh $@
