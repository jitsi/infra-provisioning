# override commands for dump, terminate, provisioning and EIP
export TERMINATE_INSTANCE_COMMAND="/usr/local/bin/terminate_instance.sh"
export PROVISION_COMMAND="provisioning"
export DUMP_COMMAND="dump"
export MAIN_COMMAND="eip_main"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

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
