# override commands for dump, terminate, provisioning and EIP
export PROVISION_COMMAND="provisioning"
export MAIN_COMMAND="eip_assign"
export PUBLIC_IP_ROLE="coturn"

function provisioning() {
  local status_code=0
  sudo /usr/local/bin/postinstall-coturn-oracle.sh >>/var/log/bootstrap.log 2>&1 || status_code=1
  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' >$tmp_msg_file
  fi

  return $status_code
}

