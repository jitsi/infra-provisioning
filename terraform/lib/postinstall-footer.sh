[ -z "$MAIN_COMMAND" ] && MAIN_COMMAND=default_main
$MAIN_COMMAND
EXIT_CODE=$?
if [ ! $EXIT_CODE -eq 0 ]; then
  if [ -f $tmp_msg_file ]; then
    err_message=$(cat $tmp_msg_file)
  else
    err_message="unknown"
  fi
  echo "Unsuccessful postinstall, error message $err_message"
  [ -z "$DUMP_COMMAND" ] && DUMP_COMMAND=default_dump
  $DUMP_COMMAND
  if [ "$SKIP_TERMINATION" != "true" ]; then
    [ -z "$TERMINATE_INSTANCE_COMMAND" ] && TERMINATE_INSTANCE_COMMAND=default_terminate
    echo "Terminating is enabled, so running terminate command $TERMINATE_INSTANCE_COMMAND"
    while true; do
      if ! oci_api_reachable; then
        restore_oci_connectivity
      fi
      $TERMINATE_INSTANCE_COMMAND && break
      echo "Terminate command $TERMINATE_INSTANCE_COMMAND failed, sleeping 60 then retrying"
      sleep 60
    done
  else
    echo "Skipping termination of instance"
  fi
  exit $EXIT_CODE
else
  echo "Successful postinstall"
  exit 0
fi
