
# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="configure-haproxy-local.yml"
export HOST_ROLE="haproxy"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

. /usr/local/bin/oracle_cache.sh
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION haproxy_boot_flag=true"
