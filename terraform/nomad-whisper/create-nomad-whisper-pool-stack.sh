#!/usr/bin/env bash
set -x 
unset SSH_USER

[ -z "$POOL_TYPE" ] && export POOL_TYPE="whisper"
[ -z "$ROLE" ] && export ROLE="whisper"
[ -z "$MEMORY_IN_GBS" ] && export MEMORY_IN_GBS="240"
[ -z "$SHAPE" ] && export SHAPE="VM.GPU.A10.1"
[ -z "$OCPUS" ] && export OCPUS="15"
[ -z "$BASE_IMAGE_TYPE" ] && export BASE_IMAGE_TYPE="GPU"
[ -z "$POSTRUNNER_PATH" ] && export POSTRUNNER_PATH="terraform/nomad-whisper/user-data/postinstall-runner-nomad-whisper-oracle.sh"
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
$LOCAL_PATH/create-nomad-whisper-instance.sh $@
