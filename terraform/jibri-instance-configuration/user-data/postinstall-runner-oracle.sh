# override dump and provision commands
export PROVISION_COMMAND="provisioning"
export DUMP_COMMAND="dump"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

function dump() {
  sudo /usr/local/bin/dump-jibri.sh
}

if [[ "$NOMAD_FLAG" == "true" ]]; then
    export PROVISION_COMMAND="nomad_provisioning"
    export HOST_ROLE="jibri"
    MY_IP=`curl -s curl http://169.254.169.254/opc/v1/vnics/ | jq .[0].privateIp -r`
    MY_COMPONENT_NUMBER="$(echo $MY_IP | awk -F. '{print $2"-"$3"-"$4}')"
    export MY_HOSTNAME="$ORACLE_REGION-$HOST_ROLE-$MY_COMPONENT_NUMBER.$DOMAIN"
fi

function nomad_provisioning() {
  VOLUME_ID=$(oci compute boot-volume-attachment list --all --region "$ORACLE_REGION" --instance-id "$INSTANCE_ID" --availability-domain "$AVAILABILITY_DOMAIN" --compartment-id "$COMPARTMENT_ID" | jq -r '.data[] | select(."lifecycle-state" == "ATTACHED") | ."boot-volume-id"')
  if [ -z "$VOLUME_ID"  ] || [ "$VOLUME_ID" == "null" ]; then
    VOLUME_ID="undefined"
  fi

  export ANSIBLE_PLAYBOOK="configure-jibri-java-local-oracle.yml"
  export ANSIBLE_VARS="cloud_name=$CLOUD_NAME hcv_environment=$ENVIRONMENT environment_domain_name=$DOMAIN prosody_domain_name=$DOMAIN oracle_region=$ORACLE_REGION oracle_instance_id=$INSTANCE_ID instance_volume_id=$VOLUME_ID autoscaler_group=$CUSTOM_AUTO_SCALE_GROUP sip_jibri_group=$CUSTOM_AUTO_SCALE_GROUP jibri_consul_datacenter=$AWS_CLOUD_NAME"

  default_provision
  return $?
}

function provisioning() {
  local status_code=0
  $TIMEOUT_BIN $PROVISIONING_TIMEOUT sudo /usr/local/bin/postinstall-jibri.sh >>/var/log/bootstrap.log 2>&1 || status_code=1
  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' >$tmp_msg_file
  fi

  return $status_code
}
