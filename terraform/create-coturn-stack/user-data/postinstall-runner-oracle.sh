# override commands for dump, terminate, provisioning and EIP
export MAIN_COMMAND="eip_assign"
export PUBLIC_IP_ROLE="coturn"

. /usr/local/bin/oracle_cache.sh

export ANSIBLE_PLAYBOOK="configure-coturn-oracle.yml"
export HOST_ROLE="coturn"
export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION environment_domain_name=$DOMAIN prosody_domain_name=$DOMAIN release_branch=$GIT_BRANCH"

function provisioning() {
  default_provision
}
