#!/bin/bash

echo "# consul-set-release-pin.sh starting"

if [ ! -z "$DEBUG" ]; then
  set -x
fi

if [  -z "$1" ]; then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "## no ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -z "$AWS_CONSUL_ENV" ] && AWS_CONSUL_ENV="prod"

if [ -z "$TENANT" ]; then
    echo "## no TENANT set, exiting"
    exit 2
fi

if [ "$PIN_ACTION" = "SET_PIN" ]; then
    if [ -z "$RELEASE_NUMBER" ]; then
        echo "## no RELEASE_NUMBER set, exiting"
        exit 2
    fi
    # string that is pushed into key value store
    RELEASE_VALUE="release-${RELEASE_NUMBER}"
elif [ "$PIN_ACTION" != "DELETE_PIN" ]; then
    echo "## ERROR: invalid PIN_ACTION: $PIN_ACTION"
    exit 2
fi

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="true"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
    echo "## creating ssh tunnel for AWS"
    PORT_AWS=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    [ -z "$AWS_LOCAL_REGION" ] && AWS_LOCAL_REGION="us-west-2"
    if [ "$AWS_CONSUL_ENV" = "dev" ]; then
        AWS_LOCAL_DATACENTER=$AWS_LOCAL_REGION-dev1
    else
        AWS_LOCAL_DATACENTER=$AWS_LOCAL_REGION-peer1
    fi
    ssh -fNT -L127.0.0.1:$PORT_AWS:consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.jitsi.net:443 $ANSIBLE_SSH_USER@$AWS_LOCAL_DATACENTER-ssh.infra.jitsi.net
    AWS_CONSUL_URL="https://consul-local.jitsi.net:$PORT_AWS"
fi

if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
    echo "## creating ssh tunnel for OCI"
    PORT_OCI=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
    [ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
    OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
    ssh -fNT -L127.0.0.1:$PORT_OCI:$OCI_LOCAL_DATACENTER-consul.jitsi.net:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.oracle.infra.jitsi.net
    OCI_CONSUL_URL="https://consul-local.jitsi.net:$PORT_OCI"
fi

FINAL_RET=0

if [ "$PIN_ACTION" = "SET_PIN" ]; then
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## AWS: pinning $TENANT to $RELEASE_VALUE"
        python ../all/bin/consul_release.py --environment $ENVIRONMENT --consul_url $AWS_CONSUL_URL pin --set $TENANT $RELEASE_VALUE
        if [ $? -gt 0 ]; then
            echo "## ERROR: failed to set pin for $TENANT in AWS"
            FINAL_RET=1
        fi
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## OCI: pinning $TENANT to $RELEASE_VALUE"
        python ../all/bin/consul_release.py --environment $ENVIRONMENT --consul_url $OCI_CONSUL_URL pin --set $TENANT $RELEASE_VALUE
        if [ $? -gt 0 ]; then
            echo "## ERROR: failed to set pin for $TENANT in OCI"
            FINAL_RET=1
        fi
    fi
elif [ "$PIN_ACTION" = "DELETE_PIN" ]; then
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        echo "## AWS: deleting pin for $TENANT"
        python ../all/bin/consul_release.py --environment $ENVIRONMENT --consul_url $AWS_CONSUL_URL pin --delete $TENANT
        if [ $? -gt 0 ]; then
            echo "## ERROR: failed to delete pin for $TENANT in AWS"
            FINAL_RET=1
        fi
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## OCI: pinning $TENANT to $RELEASE_VALUE"
        python ../all/bin/consul_release.py --environment $ENVIRONMENT --consul_url $OCI_CONSUL_URL pin --delete $TENANT
        if [ $? -gt 0 ]; then
            echo "## ERROR: failed to delete pin for $TENANT in OCI"
            FINAL_RET=1
        fi
    fi
fi

echo "## killing tunnels"
if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
    SSH_AWS_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_AWS" | awk '{print $2}')
    kill $SSH_AWS_PID
fi

if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
    SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
    kill $SSH_OCI_PID
fi

exit $FINAL_RET
