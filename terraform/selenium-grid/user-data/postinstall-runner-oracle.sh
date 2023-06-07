
# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)export ANSIBLE_PLAYBOOK="configure-selenium-grid-local-oracle.yml"
export ANSIBLE_PLAYBOOK="configure-selenium-grid-local-oracle.yml"


. /usr/local/bin/oracle_cache.sh
[ -z "$CACHE_PATH" ] && CACHE_PATH=$(ls /tmp/oracle_cache-*)
export GRID_TAG="grid"
export GRID_ROLE_TAG="grid-role"
export GRID_ROLE=$(cat $CACHE_PATH | jq -r --arg GRID_ROLE_TAG "$GRID_ROLE_TAG" ".[\"$GRID_ROLE_TAG\"]")
export GRID=$(cat $CACHE_PATH | jq -r --arg GRID_TAG "$GRID_TAG" ".[\"$GRID_TAG\"]")

export HOST_ROLE="$GRID-grid"
MY_IP=`curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r`
export MY_COMPONENT_NUMBER="$(echo $MY_IP | awk -F. '{print $2"-"$3"-"$4}')"

export MY_HOSTNAME="${ORACLE_REGION}-${HOST_ROLE}-$MY_COMPONENT_NUMBER.oracle.infra.jitsi.net"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME selenium_grid_name=$GRID selenium_grid_role=$GRID_ROLE cloud_provider=oracle region=$ORACLE_REGION oracle_region=$ORACLE_REGION"

