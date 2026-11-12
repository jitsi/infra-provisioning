# every stack reaches here, unlike configure_mirror_repos; GIT_MIRROR_HOST is set above
record_git_mirror_host
if [ "$POSTINSTALL_INTERRUPTED" == "true" ]; then
  echo "Postinstall was interrupted by a reboot" > $tmp_msg_file
  EXIT_CODE=1
else
  [ -z "$MAIN_COMMAND" ] && MAIN_COMMAND=default_main
  $MAIN_COMMAND
  EXIT_CODE=$?
fi
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
  rm -f "$POSTINSTALL_MARKER" "$POSTINSTALL_GUARD"
  exit 0
fi
