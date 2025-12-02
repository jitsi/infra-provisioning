# nomad customizations for skynet-cpu pools

# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="nomad-client.yml"

. /usr/local/bin/oracle_cache.sh
[ -z "$CACHE_PATH" ] && CACHE_PATH=$(ls /tmp/oracle_cache-*)
export POOL_TYPE_TAG="pool_type"
export POOL_TYPE=$(cat $CACHE_PATH | jq -r --arg POOL_TYPE_TAG "$POOL_TYPE_TAG" ".[\"$POOL_TYPE_TAG\"]")
if [[ "$POOL_TYPE" == "null" ]]; then
    export POOL_TYPE=
fi
[ -z "$POOL_TYPE" ] && POOL_TYPE="skynet-cpu"
export HOST_ROLE="skynetc"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION nomad_pool_type=$POOL_TYPE skynet_models_flag=true"
