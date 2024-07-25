# override dump and provision commands
export PROVISION_COMMAND="provisioning"
export DUMP_COMMAND="dump"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

function dump() {
  sudo /usr/local/bin/dump-jibri.sh
}

if [[ "$NOMAD_FLAG" == "true" ]]; then
    . /usr/local/bin/oracle_cache.sh
    [ -z "$CACHE_PATH" ] && CACHE_PATH=$(ls /tmp/oracle_cache-*)
    export POOL_TYPE_TAG="pool_type"
    export POOL_TYPE=$(cat $CACHE_PATH | jq -r --arg POOL_TYPE_TAG "$POOL_TYPE_TAG" ".[\"$POOL_TYPE_TAG\"]")
    if [[ "$POOL_TYPE" == "null" ]]; then
        export POOL_TYPE=
    fi
    [ -z "$POOL_TYPE" ] && POOL_TYPE="jibri"

    VOLUME_ID=$(oci compute boot-volume-attachment list --all --region "$ORACLE_REGION" --instance-id "$INSTANCE_ID" --availability-domain "$AVAILABILITY_DOMAIN" --compartment-id "$COMPARTMENT_ID" | jq -r '.data[] | select(."lifecycle-state" == "ATTACHED") | ."boot-volume-id"')
    if [ -z "$VOLUME_ID"  ] || [ "$VOLUME_ID" == "null" ]; then
      VOLUME_ID="undefined"
    fi

    export ANSIBLE_PLAYBOOK="nomad-client.yml"
    export ANSIBLE_VARS="hcv_environment=$ENVIRONMENT cloud_name=$CLOUD_NAME cloud_provider=oracle oracle_region=$ORACLE_REGION region=$ORACLE_REGION nomad_pool_type=$POOL_TYPE autoscaler_group=$CUSTOM_AUTO_SCALE_GROUP instance_volume_id=$VOLUME_ID  oracle_instance_id=$INSTANCE_ID autoscaler_server_host=$ENVIRONMENT-$ORACLE_REGION-autoscaler.jitsi.net nomad_enable_jitsi_autoscaler=true"
    export PROVISION_COMMAND="default_provision"
    export HOST_ROLE="jibri"
    MY_IP=`curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r`
    MY_COMPONENT_NUMBER="$(echo $MY_IP | awk -F. '{print $2"-"$3"-"$4}')"
    export MY_HOSTNAME="$ENVIRONMENT-$HOST_ROLE-$MY_COMPONENT_NUMBER.$DOMAIN"
fi

function provisioning() {
  local status_code=0
  $TMBIN $PTIMEOUT sudo /usr/local/bin/postinstall-jibri.sh >>/var/log/bootstrap.log 2>&1 || status_code=1
  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' >$tmp_msg_file
  fi

  return $status_code
}
