
# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="configure-jumpbox.yml"
export HOST_ROLE="ssh"

. /usr/local/bin/oracle_cache.sh
export MY_HOSTNAME="${CLOUD_NAME}-${HOST_ROLE}.oracle.infra.jitsi.net"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION"
