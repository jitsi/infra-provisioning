
# run main function implemented by specific role
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

    $TERMINATE_INSTANCE_COMMAND

  else
    echo "Skipping termination of instance"
  fi

  exit $EXIT_CODE
else
  echo "Successful postinstall"
  exit 0
fi
