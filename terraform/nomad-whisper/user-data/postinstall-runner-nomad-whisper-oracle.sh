#!/bin/bash

# nomad customizations

# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="nomad-client.yml"

. /usr/local/bin/oracle_cache.sh
[ -z "$CACHE_PATH" ] && CACHE_PATH=$(ls /tmp/oracle_cache-*)
export POOL_TYPE_TAG="pool_type"
export POOL_TYPE="whisper"
export HOST_ROLE="gpu"
export GPU_COUNT="$(nvidia-smi --list-gpus | wc -l)"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION nomad_pool_type=$POOL_TYPE nomad_gpu_count=$GPU_COUNT autoscaler_group=$CUSTOM_AUTO_SCALE_GROUP autoscaler_server_host=$ENVIRONMENT-$ORACLE_REGION-autoscaler.jitsi.net nvidia_docker_flag=true nomad_enable_jitsi_autoscaler=true"
