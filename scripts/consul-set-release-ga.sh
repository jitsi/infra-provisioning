#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

echo "## starting consul-set-release-ga.sh"

set -x

if [  -z "$1" ]; then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 1
fi

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER set, exiting"
    exit 1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . $LOCAL_PATH/../clouds/all.sh

# string that is pushed into key value store
RELEASE_VALUE="release-${RELEASE_NUMBER}"

# string path where value is stored, combined with 
KV_KEY="releases/$ENVIRONMENT/live"

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="true"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"
[ -z "$CONSUL_VIA_SSH" ] && CONSUL_VIA_SSH="false"

[ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"

CONSUL_AWS_HOST="consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.$TOP_LEVEL_DNS_ZONE_NAME"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
    echo "## consul-set-release-ga: setting up ssh tunnels for consul"
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        echo "## create ssh connection to AWS consul"
        PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
        [ -z "$AWS_LOCAL_DATACENTER" ] && AWS_LOCAL_DATACENTER="us-east-1-peer1"
        [ -z "$AWS_CONSUL_ENV" ] && AWS_CONSUL_ENV="prod"
        ssh -fNT -L127.0.0.1:$PORT:consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.jitsi.net:443 $ANSIBLE_SSH_USER@$AWS_LOCAL_DATACENTER-ssh.infra.jitsi.net
        CONSUL_URL="https://consul-local.jitsi.net:$PORT"
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## create ssh connection to OCI consul"
        PORT_OCI=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
        [ -z "$OCI_LOCAL_REGION" ] && OCI_LOCAL_REGION="us-phoenix-1"
        OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"
        ssh -fNT -L127.0.0.1:$PORT_OCI:$OCI_LOCAL_DATACENTER-consul.jitsi.net:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.oracle.infra.jitsi.net
        OCI_CONSUL_URL="https://consul-local.jitsi.net:$PORT_OCI"
    fi
else
    CONSUL_HOST="$AWS_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        CONSUL_URL="https://$CONSUL_AWS_HOST"
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        OCI_CONSUL_URL="https://$CONSUL_OCI_HOST"
    fi
fi

echo "## consul-set-release-ga: CONSUL_URL: $CONSUL_URL"
echo "## consul-set-release-ga: OCI_CONSUL_URL: $OCI_CONSUL_URL"

if [ -z "$DATACENTER" ] && [ ! -z "$REGION" ]; then
    DATACENTER="$REGION-peer1"
fi

[ ! -z "$DATACENTER" ] && DATACENTERS="[\"$DATACENTER\"]"

if [ -z "$DATACENTERS" ]; then
    DATACENTERS='[]'

    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        echo "## get AWS datacenters from consul"
        AWS_DATACENTERS=$(curl -G $CONSUL_URL/v1/catalog/datacenters 2>/tmp/dclist)
        if [[ $? -gt 0 ]]; then
            AWS_DATACENTERS='[]'
        fi
    else
        AWS_DATACENTERS='[]'
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## get OCI datacenters from consul"
        OCI_DATACENTERS=$(curl -G $OCI_CONSUL_URL/v1/catalog/datacenters 2>>/tmp/dclist)
        if [[ $? -gt 0 ]]; then
            OCI_DATACENTERS='[]'
        fi
    else
        OCI_DATACENTERS='[]'
    fi
    DATACENTERS=$(jq -c -n --argjson aws "$AWS_DATACENTERS" --argjson oci "$OCI_DATACENTERS" '{"aws":$aws, "oci":$oci}|.aws+.oci')
    OCI_DATACENTERS=$(echo $OCI_DATACENTERS| jq -r ".[]")
    AWS_DATACENTERS=$(echo $AWS_DATACENTERS| jq -r ".[]")
fi

if [[ ! -z "$DATACENTERS" && "$DATACENTERS" != '[]' ]]; then
    FINAL_RET=0
    ALL_DATACENTERS=$(echo $DATACENTERS| jq -r ".[]")

    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        for DC in $AWS_DATACENTERS; do
            KV_URL="$CONSUL_URL/v1/kv/$KV_KEY?dc=$DC"
            RESPONSE=$(curl -d"$RELEASE_VALUE" -X PUT $KV_URL)
            if [ $? -gt 0 ]; then
                echo "Failed setting release in $DC"
                FINAL_RET=3
            fi
        done
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        for DC in $OCI_DATACENTERS; do
            KV_URL="$OCI_CONSUL_URL/v1/kv/$KV_KEY?dc=$DC"
            RESPONSE=$(curl -d"$RELEASE_VALUE" -X PUT $KV_URL)
            if [ $? -gt 0 ]; then
                echo "Failed setting release in $DC"
                FINAL_RET=3
            fi
        done
    fi
else
    echo "No datacenters set or found, exiting"
    FINAL_RET=2
fi

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
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