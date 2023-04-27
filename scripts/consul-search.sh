#!/bin/bash

#set -x

if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="false"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

[ -z "$AWS_LOCAL_DATACENTER" ] && AWS_LOCAL_DATACENTER="us-east-1-peer1"
[ -z "$AWS_CONSUL_ENV" ] && AWS_CONSUL_ENV="prod"
[ -z "$CONSUL_VIA_SSH" ] && CONSUL_VIA_SSH="true"

OCI_LOCAL_REGION="us-phoenix-1"
OCI_LOCAL_DATACENTER="$ENVIRONMENT-$OCI_LOCAL_REGION"

CONSUL_AWS_HOST="consul-$AWS_CONSUL_ENV-$AWS_LOCAL_DATACENTER.$TOP_LEVEL_DNS_ZONE_NAME"
CONSUL_OCI_HOST="$OCI_LOCAL_DATACENTER-consul.$TOP_LEVEL_DNS_ZONE_NAME"

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
    CONSUL_HOST="consul-local.$TOP_LEVEL_DNS_ZONE_NAME"

    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
        ssh -o StrictHostKeyChecking=no -fNT -L127.0.0.1:$PORT:$CONSUL_AWS_HOST:443 $ANSIBLE_SSH_USER@$AWS_LOCAL_DATACENTER-ssh.$INFRA_DNS_ZONE_NAME
        CONSUL_URL="https://$CONSUL_HOST:$PORT"
        AWS_CURL_OPTS=" --resolve $CONSUL_HOST:$PORT:127.0.0.1"
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        PORT_OCI=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
        ssh -o StrictHostKeyChecking=no -fNT -L127.0.0.1:$PORT_OCI:$CONSUL_OCI_HOST:443 $ANSIBLE_SSH_USER@$OCI_LOCAL_REGION-$ENVIRONMENT-ssh.$DEFAULT_DNS_ZONE_NAME
        OCI_CONSUL_URL="https://$CONSUL_HOST:$PORT_OCI"
        OCI_CURL_OPTS=" --resolve $CONSUL_HOST:$PORT_OCI:127.0.0.1"
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

[ -z "$FILTER_ENVIRONMENT" ] && FILTER_ENVIRONMENT="true";

if [ "$FILTER_ENVIRONMENT" == "true" ]; then
    FILTER_DATA="filter=ServiceMeta.environment == \"$ENVIRONMENT\""
fi
[ -z "$RELEASE_INVERSE" ] && RELEASE_INVERSE="false"

RELEASE_OPERATOR="=="
[[ "$RELEASE_INVERSE" == "true" ]] && RELEASE_OPERATOR="!="

[ ! -z "$RELEASE_NUMBER" ] && FILTER_DATA="$FILTER_DATA and ServiceMeta.release_number $RELEASE_OPERATOR \"$RELEASE_NUMBER\""
[ ! -z "$SHARD" ] && FILTER_DATA="$FILTER_DATA and ServiceMeta.shard == \"$SHARD\""

if [ -z "$DATACENTER" ] && [ ! -z "$REGION" ]; then
    DATACENTER="$REGION-peer1"
fi

[ -z "$SERVICE" ] && SERVICE="signal"
[ -z "$DISPLAY" ] && DISPLAY="shards"

[ ! -z "$DATACENTER" ] && DATACENTERS="[\"$DATACENTER\"]"

if [ -z "$DATACENTERS" ]; then
    DATACENTERS='[]'
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        AWS_DATACENTERS=$(curl $AWS_CURL_OPTS -G $CONSUL_URL/v1/catalog/datacenters 2>/tmp/dclist)
        if [[ $? -gt 0 ]]; then
            AWS_DATACENTERS='[]'
        fi
    else
        AWS_DATACENTERS='[]'
    fi    
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        OCI_DATACENTERS=$(curl $OCI_CURL_OPTS -G $OCI_CONSUL_URL/v1/catalog/datacenters 2>>/tmp/dclist)
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
    ALL_DATACENTERS=$(echo $DATACENTERS| jq -r ".[]")
#    echo $ALL_DATACENTERS
#    OTHER_DATACENTERS=$(echo $DATACENTERS| jq -r ".|map(select(. != \"$LOCAL_DATACENTER\"))|.[]")
    ALL_RELEASES=""
    ALL_SHARDS=""
    ALL_ADDRESSES=""
    ALL_SERVICES=""
    ALL_URLS=""
    ALL_CORE_PROVIDERS=""
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        for DC in $AWS_DATACENTERS; do
            # TO FIX: this doesn't distinguish whether the raft members are in active/left/failed states
            SERVICES=$(curl $AWS_CURL_OPTS -G $CONSUL_URL/v1/catalog/service/${SERVICE}?dc=$DC --data-urlencode "$FILTER_DATA" 2>/tmp/servicecataloglist)
            if [ $? -eq 0 ]; then
    #            echo $SERVICES
                [ "$SERVICES" == "null" ] && SERVICES=""
                ADDRESSES=$(echo $SERVICES | jq -r ".|map(.Address)|.[]")
                URLS=$(echo $SERVICES | jq -r '.|map("http://"+.Address+":"+(.ServicePort|tostring))|.[]')
                RELEASES=$(echo $SERVICES | jq -r ".|map(.ServiceMeta.release_number)|unique|.[]")
                SHARDS=$(echo $SERVICES | jq -r ".|map(.ServiceMeta.shard)|unique|.[]")
                ALL_SHARDS="$SHARDS $ALL_SHARDS"
                ALL_URLS="$URLS $ALL_URLS"
                ALL_SERVICES="$SERVICES $ALL_SERVICES"
                ALL_RELEASES="$RELEASES $ALL_RELEASES"
                ALL_ADDRESSES="$ADDRESSES $ALL_ADDRESSES"
                [ ! -z "$SHARDS" ] && ALL_CORE_PROVIDERS="aws"
            fi
        done
    fi
    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        for DC in $OCI_DATACENTERS; do
            # TO FIX: this doesn't distinguish whether the raft members are in active/left/failed states
            SERVICES=$(curl $OCI_CURL_OPTS -G $OCI_CONSUL_URL/v1/catalog/service/${SERVICE}?dc=$DC --data-urlencode "$FILTER_DATA" 2>>/tmp/servicecataloglist)
            if [ $? -eq 0 ]; then
    #            echo $SERVICES
                [ "$SERVICES" == "null" ] && SERVICES=""
                if [ ! -z "$SERVICES" ]; then
                    echo "$SERVICES" | jq '.' > /dev/null
                    if [ $? -eq 0 ]; then
                        ADDRESSES="$(echo $SERVICES | jq -r ".|map(.Address)|.[]")"
                        URLS=$(echo $SERVICES | jq -r '.|map("http://"+.Address+":"+(.ServicePort|tostring))|.[]')
                        RELEASES="$(echo $SERVICES | jq -r ".|map(.ServiceMeta.release_number)|unique|.[]")"
                        SHARDS="$(echo $SERVICES | jq -r ".|map(.ServiceMeta.shard)|unique|.[]")"0
                        SERVICE_META="$(echo $SERVICES | jq -r ".|map(.ServiceMeta)")"
                        ALL_SHARDS="$SHARDS $ALL_SHARDS"
                        ALL_URLS="$URLS $ALL_URLS"
                        ALL_SERVICES="$SERVICES $ALL_SERVICES"
                        ALL_RELEASES="$RELEASES $ALL_RELEASES"
                        ALL_ADDRESSES="$ADDRESSES $ALL_ADDRESSES"
                        ALL_SERVICE_META="$(echo "$ALL_SERVICE_META" "$SERVICE_META" | jq -c -s '.|add')"
                        if [ ! -z "$SHARDS" ]; then
                            for S in $SHARDS; do
                                ALLOCATION="$(echo "$SERVICES" | jq -r ".|map(select(.ServiceMeta.shard==\"$S\"))|.[].ServiceMeta.nomad_allocation")"
                                if [[ "$ALLOCATION" != "null" ]]; then
                                    ALL_CORE_PROVIDERS="nomad $ALL_CORE_PROVIDERS"
                                else
                                    ALL_CORE_PROVIDERS="oracle $ALL_CORE_PROVIDERS"
                                fi
                            done
                        fi
                    fi
                fi
            fi
        done
    fi
    ALL_RELEASES=$(echo $ALL_RELEASES | xargs -n1 | sort -u)
    ALL_ADDRESSES=$(echo $ALL_ADDRESSES | xargs -n1 | sort -u)
    ALL_SHARDS=$(echo $ALL_SHARDS | xargs -n1 | sort -u)
    ALL_CORE_PROVIDERS=$(echo $ALL_CORE_PROVIDERS | xargs -n1 | sort -u)
    ALL_URLS=$(echo $ALL_URLS | xargs -n1 | sort -u)

    [ "$DISPLAY" == "releases" ] && echo $ALL_RELEASES
    [ "$DISPLAY" == "shards" ] && echo $ALL_SHARDS
    [ "$DISPLAY" == "addresses" ] && echo $ALL_ADDRESSES
    [ "$DISPLAY" == "core_providers" ] && echo $ALL_CORE_PROVIDERS
    [ "$DISPLAY" == "service_meta" ] && echo $ALL_SERVICE_META
    [ "$DISPLAY" == "service" ] && echo $ALL_SERVICES
    [ "$DISPLAY" == "urls" ] && echo $ALL_URLS
else
    if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
        if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
            SSH_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT" | awk '{print $2}')
            kill $SSH_PID
        fi
    fi

    if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
        if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
            SSH_OCI_PID=$(ps auxww | grep "ssh \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
            kill $SSH_OCI_PID
        fi
    fi

    echo "NO DATACENTERS FOUND OR PROVIDED, EXITING"
    exit 1
fi

if [[ "$CONSUL_VIA_SSH" == "true" ]]; then
    if [[ "$CONSUL_INCLUDE_AWS" == "true" ]]; then
        SSH_PID=$(ps auxww | grep "ssh \-o StrictHostKeyChecking=no \-fNT -L127.0.0.1:$PORT" | awk '{print $2}')
        kill $SSH_PID
    fi

    if [[ "$CONSUL_INCLUDE_OCI" == "true" ]]; then
        SSH_OCI_PID=$(ps auxww | grep "ssh \-o StrictHostKeyChecking=no \-fNT -L127.0.0.1:$PORT_OCI" | awk '{print $2}')
        kill $SSH_OCI_PID
    fi
fi