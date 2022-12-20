export DUMP_COMMAND="dump"
export PROVISION_COMMAND="provisioning"

function dump() {
  default_dump
#  sudo /usr/local/bin/dump-standalone.sh
}

function provisioning() {
  local status_code=0
  
  $TIMEOUT_BIN $PROVISIONING_TIMEOUT echo "provisioning standalone" >>/var/log/bootstrap.log 2>&1 || status_code=1

  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' > $tmp_msg_file;
  fi

  return $status_code;
}
