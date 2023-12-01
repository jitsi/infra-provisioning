# override commands for dump, terminate, provisioning and EIP
export TERMINATE_INSTANCE_COMMAND="/usr/local/bin/terminate_instance.sh"
export PROVISION_COMMAND="provisioning"
export DUMP_COMMAND="dump"
export MAIN_COMMAND="eip_main"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

if [[ "$NOMAD_FLAG" == "true" ]]; then
    . /usr/local/bin/oracle_cache.sh
    [ -z "$POOL_TYPE" ] && POOL_TYPE="JVB"

    export ANSIBLE_PLAYBOOK="nomad-client.yml"
    export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION nomad_pool_type=$POOL_TYPE autoscaler_group=$CUSTOM_AUTO_SCALE_GROUP oracle_instance_id=$INSTANCE_ID autoscaler_server_host=$ENVIRONMENT-$ORACLE_REGION-autoscaler.jitsi.net nomad_enable_jitsi_autoscaler=true"
    export PROVISION_COMMAND="default_provision"
    export HOST_ROLE="jvb"
    MY_IP=`curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r`
    MY_COMPONENT_NUMBER="$(echo $MY_IP | awk -F. '{print $2"-"$3"-"$4}')"
    export MY_HOSTNAME="$ENVIRONMENT-$HOST_ROLE-$MY_COMPONENT_NUMBER.$DOMAIN"
fi

function dump() {
  sudo /usr/local/bin/dump-jvb.sh
}

function provisioning() {
  local status_code=0
  sudo /usr/local/bin/postinstall-jvb-oracle.sh >>/var/log/bootstrap.log 2>&1 || status_code=1
  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' >$tmp_msg_file
  fi

  return $status_code
}
