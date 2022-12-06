#!/bin/bash -v
set -x
EXIT_CODE=0
tmp_msg_file='/tmp/postinstall_runner_message'
TIMEOUT_BIN="/usr/bin/timeout"
PROVISIONING_TIMEOUT="1200"
