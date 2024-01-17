#!/bin/bash
[ -z "$LOCAL_DEV_DIR" ] && LOCAL_DEV_DIR="$(realpath "$HOME/dev")"
[ -z "$ASAP_KEY_DIR" ] && ASAP_KEY_DIR="/opt/jitsi/keys"
[ -z "$OPS_AGENT_VERSION" ] && OPS_AGENT_VERSION="latest"

docker run -v ~/.ssh:/home/jenkins/.ssh \
  -v $LOCAL_DEV_DIR/infra-provisioning:/home/jenkins/infra-provisioning \
  -v $LOCAL_DEV_DIR/infra-configuration:/home/jenkins/infra-configuration \
  -v $LOCAL_DEV_DIR/infra-customizations-private:/home/jenkins/infra-customizations-private \
  -v $ASAP_KEY_DIR:/opt/jitsi/keys \
  -it aaronkvanmeerten/ops-agent:$OPS_AGENT_VERSION
