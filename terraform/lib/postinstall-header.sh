#!/bin/bash -v
set -x
EXIT_CODE=0
tmp_msg_file='/tmp/postinstall_runner_message'
TIMEOUT_BIN="/usr/bin/timeout"
PROVISIONING_TIMEOUT="1200"
# cloud-init runs user-data once per instance, so a reboot mid-postinstall needs a per-boot hook; the marker lives in the per-instance dir so one baked into an image is ignored
POSTINSTALL_MARKER="/var/lib/cloud/instance/postinstall-in-progress"
POSTINSTALL_GUARD="/var/lib/cloud/scripts/per-boot/postinstall-interrupted.sh"
if [ -f "$POSTINSTALL_MARKER" ]; then
  POSTINSTALL_INTERRUPTED="true"
else
  touch "$POSTINSTALL_MARKER"
  mkdir -p "$(dirname "$POSTINSTALL_GUARD")"
  printf '#!/bin/bash\n[ -f %s ] || exit 0\nexec %s\n' "$POSTINSTALL_MARKER" "$(readlink -f "$0")" > "$POSTINSTALL_GUARD"
  chmod 755 "$POSTINSTALL_GUARD"
fi
