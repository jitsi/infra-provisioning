
# with no overrides, provision based on the variables below using default_provision
# default_provision takes the following variables ANSIBLE_PLAYBOOK, ANSIBLE_VARS and HOST_ROLE (defaults to $SHARD_ROLE)
export ANSIBLE_PLAYBOOK="configure-firezone.yml"
export HOST_ROLE="vpn"

. /usr/local/bin/oracle_cache.sh
export MY_HOSTNAME="${ORACLE_REGION}-${ENVIRONMENT}-${HOST_ROLE}.oracle.infra.jitsi.net"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION dns_name=$MY_HOSTNAME"

## generate config file that sets up ssl certificates from firezone_ssl_certificates