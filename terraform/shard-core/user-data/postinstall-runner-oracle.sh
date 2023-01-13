export DUMP_COMMAND="dump"

# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="configure-core-local.yml"
export HOST_ROLE="core"

. /usr/local/bin/oracle_cache.sh
[ -z "$CACHE_PATH" ] && CACHE_PATH=$(ls /tmp/oracle_cache-*)
export VISITORS_ENABLED_TAG="visitors_enabled"
export VISITORS_ENABLED=$(cat $CACHE_PATH | jq -r --arg VISITORS_ENABLED_TAG "$VISITORS_ENABLED_TAG" ".[\"$VISITORS_ENABLED_TAG\"]")
export VISITORS_COUNT_TAG="visitors_count"
export VISITORS_COUNT=$(cat $CACHE_PATH | jq -r --arg VISITORS_COUNT_TAG "$VISITORS_COUNT_TAG" ".[\"$VISITORS_COUNT_TAG\"]")

SHARD_NUMBER=$(echo $SHARD| rev | cut -d"-" -f1 | rev | tr -d '[:alpha:]')
export MY_HOSTNAME="$SHARD.$DOMAIN"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT shard=$SHARD cloud_name=$CLOUD_NAME cloud_provider=oracle core_cloud_provider=oracle region=$ORACLE_REGION oracle_region=$ORACLE_REGION prosody_domain_name=$DOMAIN shard_name=$SHARD jitsi_release_number=$RELEASE_NUMBER shard_number=$SHARD_NUMBER visitors_enabled=$VISITORS_ENABLED visitors_count=$VISITORS_COUNT"

function dump() {
  sudo /usr/local/bin/dump-jicofo.sh
}
