# override dump and provision commands
export PROVISION_COMMAND="provisioning"
export DUMP_COMMAND="dump"
# do not clean up credentials, re-used on reconfiguration
export CLEAN_CREDENTIALS="false"

if [[ "$VAULT_FLAG" == "true" ]]; then
  [ -f "/lib/systemd/system/vault-proxy.service" ] && service vault-proxy start
fi

function dump() {
  sudo /usr/local/bin/dump-jigasi.sh
}

function provisioning() {
  local status_code=0
  
  $TIMEOUT_BIN $PROVISIONING_TIMEOUT /usr/local/bin/postinstall-jigasi.sh >>/var/log/bootstrap.log 2>&1 || status_code=1

  if [ $status_code -eq 1 ]; then
    echo 'Provisioning stage failed' > $tmp_msg_file;
  fi

  return $status_code;
}
