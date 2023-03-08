#!/bin/bash

[ -e ./stack-env.sh ] && . ./stack-env.sh

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 1
fi

INPUT_VALID=false
[ -n "$BAN_ROOM" ] && INPUT_VALID=true
[ -n "$BAN_TENANT" ] && INPUT_VALID=true
[ -n "$UNBAN_ROOM" ] && INPUT_VALID=true
[ -n "$UNBAN_TENANT" ] && INPUT_VALID=true

if ! $INPUT_VALID; then
    echo "No valid input found, requires BAN_ROOM, BAN_TENANT, UNBAN_ROOM or UNBAN_TENANT value to be set"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

BAN_VALUE="ban"
CONSUL_HOST="consul-local.$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="false"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

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
    OCI_CONSUL_URL="https://$CONSUL_HOST:$PORT_OCI"
fi

if [ -z "$DATACENTER" ] && [ ! -z "$REGION" ]; then
    DATACENTER="$REGION-peer1"
fi

[ -z "$SERVICE" ] && SERVICE="signal"
[ -z "$DISPLAY" ] && DISPLAY="shards"

[ ! -z "$DATACENTER" ] && DATACENTERS="[\"$DATACENTER\"]"

function loopDataCenters {
    KV=$1
    DC_LIST=$2
    URL=$3
    METHOD="${4:-PUT}"
    [[ "$METHOD" == "PUT" ]] && CURL_PARAM="-d$BAN_VALUE"

    DC_RET=0
    for DC in $DC_LIST; do
        KV_URL="$URL/v1/kv/$KV?dc=$DC"
        RESPONSE=$(curl --resolve $CONSUL_HOST:$PORT_OCI:127.0.0.1 --resolve $CONSUL_HOST:$PORT:127.0.0.1 $CURL_PARAM -X $METHOD $KV_URL)
        if [ $? -gt 0 ]; then
            echo "Failed setting release in $DC"
            echo "RESPONSE: $RESPONSE"
            DC_RET=3
        fi
    done
    return $DC_RET
}

function loopCloudProviders {
    KV_KEY=$1
    CMETHOD="${2:-PUT}"
    PRET=0
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        loopDataCenters $KV_KEY "$AWS_DATACENTERS" $CONSUL_URL $CMETHOD
        LRET=$?
        if [ $LRET -gt 0 ]; then
            PRET=$LRET
        fi
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        loopDataCenters $KV_KEY "$OCI_DATACENTERS" $OCI_CONSUL_URL $CMETHOD
        LRET=$?
        if [ $LRET -gt 0 ]; then
            PRET=$LRET
        fi
    fi
    return $PRET
}

if [ -z "$DATACENTERS" ]; then
    DATACENTERS='[]'

    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        echo "## get AWS datacenters from consul"
        AWS_DATACENTERS=$(curl --resolve $CONSUL_HOST:$PORT:127.0.0.1 -G $CONSUL_URL/v1/catalog/datacenters 2>/tmp/dclist)
        if [[ $? -gt 0 ]]; then
            AWS_DATACENTERS='[]'
        fi
    else
        AWS_DATACENTERS='[]'
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        echo "## get OCI datacenters from consul"
        OCI_DATACENTERS=$(curl --resolve $CONSUL_HOST:$PORT_OCI:127.0.0.1 -G $OCI_CONSUL_URL/v1/catalog/datacenters 2>>/tmp/dclist)
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

if [ ! -z "$DATACENTERS" ]; then
    FINAL_RET=0
    ALL_DATACENTERS=$(echo $DATACENTERS| jq -r ".[]")

    if [ -n "$BAN_ROOM" ]; then
        # string path where value is stored, combined with 
        loopCloudProviders "bans/$ENVIRONMENT/room/$BAN_ROOM"
        LOOP_RET=$?
        if [[ $LOOP_RET -gt 0 ]]; then
            FINAL_RET=$LOOP_RET
        fi
    fi
    if [ -n "$UNBAN_ROOM" ]; then
        loopCloudProviders "bans/$ENVIRONMENT/room/$UNBAN_ROOM" "DELETE"
        LOOP_RET=$?
        if [[ $LOOP_RET -gt 0 ]]; then
            FINAL_RET=$LOOP_RET
        fi
    fi
    if [ -n "$BAN_TENANT" ]; then
        # string path where value is stored, combined with 
        loopCloudProviders "bans/$ENVIRONMENT/tenant/$BAN_TENANT"
        LOOP_RET=$?
        if [[ $LOOP_RET -gt 0 ]]; then
            FINAL_RET=$LOOP_RET
        fi
    fi
    if [ -n "$UNBAN_TENANT" ]; then
        loopCloudProviders "bans/$ENVIRONMENT/tenant/$UNBAN_TENANT" "DELETE"
        LOOP_RET=$?
        if [[ $LOOP_RET -gt 0 ]]; then
            FINAL_RET=$LOOP_RET
        fi
    fi
else
    echo "No datacenters set or found, exiting"
    FINAL_RET=2
fi

if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
    SSH_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT" | awk '{print $2}')
    kill $SSH_PID
fi

if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
    SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
    kill $SSH_OCI_PID
fi

exit $FINAL_RET