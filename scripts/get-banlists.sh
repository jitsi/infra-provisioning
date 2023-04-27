#!/bin/bash

echo "## starting get-banlists.sh"

if [  -z "$1" ]; then
    ANSIBLE_SSH_USER=$(whoami)
else
    ANSIBLE_SSH_USER=$1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "## ERROR: no ENVIRONMENT set, exiting..."
    exit 1
fi

if [ -z "$BAN_TYPES" ] || [ "$BAN_TYPES" == "ALL" ]; then
    BAN_TYPES="domain exact prefix substr"
fi

for ban_type in $BAN_TYPES; do
    if [[ ! "$ban_type" =~ ^(ALL|domain|exact|prefix|substr)$ ]]; then
        echo "## ERROR: ban types can only be domain, exact, prefix, or substr"
        exit 1
    fi
done

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$CONSUL_VIA_SSH" ] && CONSUL_VIA_SSH="false"
[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="false"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

AWS_LOCAL_DATACENTER="$REGION-peer1"

OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"

CONSUL_AWS_HOST="consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.$TOP_LEVEL_DNS_ZONE_NAME"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
    echo "## getting consul banlists via curl over ssh"
    CONSUL_HOST="consul-local.$TOP_LEVEL_DNS_ZONE_NAME"
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        echo "## create ssh connection to AWS consul"
        PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
        [ -z "$AWS_LOCAL_DATACENTER" ] && AWS_LOCAL_DATACENTER="us-east-1-peer1"
        [ -z "$AWS_CONSUL_ENV" ] && AWS_CONSUL_ENV="prod"
        ssh -o StrictHostKeyChecking=no -fNT -L127.0.0.1:$PORT:consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.$TOP_LEVEL_DNS_ZONE_NAME:443 $ANSIBLE_SSH_USER@$AWS_LOCAL_DATACENTER-ssh.infra.jitsi.net
        CONSUL_URL="https://$CONSUL_HOST:$PORT"
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## create ssh connection to OCI consul"
        PORT_OCI="$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
        OCI_LOCAL_REGION="us-phoenix-1"
        OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
        ssh -o StrictHostKeyChecking=no -fNT -L127.0.0.1:$PORT_OCI:$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.oracle.infra.jitsi.net
        OCI_CONSUL_URL="https://$CONSUL_OCI:$PORT_OCI"
    fi
else
    echo "## getting consul banlists via direct curls"
    CONSUL_HOST="$AWS_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        CONSUL_URL="https://$CONSUL_AWS_HOST"
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
    fi
fi

FINAL_RET=0

for ban_type in $BAN_TYPES; do
    CONSUL_KEY_PATH="v1/kv/banlists/$ENVIRONMENT/$ban_type"

    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        KV_URL="$CONSUL_URL/$CONSUL_KEY_PATH?dc=$AWS_LOCAL_DATACENTER&recurse"
        RESPONSE=$(curl $KV_URL)
        if [ $? -gt 0 ]; then
            echo "## did not find bans of type $BAN_TYPE in $AWS_LOCAL_DATACENTER"
        else
            echo "## bans of type $ban_type:"
            echo $RESPONSE | jq -r '.[].Key' | rev | cut -d\/ -f1 | rev
        fi
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        KV_URL="$OCI_CONSUL_URL/$CONSUL_KEY_PATH?dc=$OCI_LOCAL_DATACENTER&recurse"
        RESPONSE=$(curl -s $KV_URL)
        if [ $? -gt 0 ]; then
            echo "## did not find bans of type $BAN_TYPE in $OCI_LOCAL_DATACENTER"
        else
            echo "## bans of type $ban_type:"
            echo $RESPONSE | jq -r '.[].Key' | rev | cut -d\/ -f1 | rev
        fi
    fi
done

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
    echo "## killing ssh processes"
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        SSH_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT" | awk '{print $2}')
        kill $SSH_PID
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
        kill $SSH_OCI_PID
    fi
fi

exit $FINAL_RET