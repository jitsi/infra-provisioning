#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -e "./stack-env.sh" ]; then 
    . ./stack-env.sh
else
    if [ ! -z "$ENVIRONMENT" ]; then
        . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh
    fi
fi

[ -z "$DEFAULT_DNS_ZONE_NAME" ] && DEFAULT_DNS_ZONE_NAME="oracle.infra.jitsi.net"

#set -x

ACTION=$1

if [  -z "$2" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$2
fi

[ -z "$SHARDS_FROM_CONSUL" ] && SHARDS_FROM_CONSUL="false"

[ -z "$CONSUL_INCLUDE_AWS" ] && CONSUL_INCLUDE_AWS="true"
[ -z "$CONSUL_INCLUDE_OCI" ] && CONSUL_INCLUDE_OCI="true"

function list() {
    [ -z "$RELEASE_INVERSE" ] && RELEASE_INVERSE="false"
    if [[ "$SHARDS_FROM_CONSUL" == "true" ]]; then
        CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" RELEASE_INVERSE="$RELEASE_INVERSE" RELEASE_NUMBER="$RELEASE_NUMBER" ENVIRONMENT="$ENVIRONMENT" DISPLAY="shards" SERVICE="signal" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER
    else
        [ ! -z "$RELEASE_NUMBER" ] && RELEASE_PARAM="--release $RELEASE_NUMBER"
        $LOCAL_PATH/shard.py --environment=$ENVIRONMENT --list $RELEASE_PARAM
    fi
}

function list_releases() {
    if [[ "$SHARDS_FROM_CONSUL" == "true" ]]; then
        CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" ENVIRONMENT="$ENVIRONMENT" DISPLAY="releases" SERVICE="signal" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER
    else
        $LOCAL_PATH/shard.py --environment=$ENVIRONMENT --list_releases $RELEASE_PARAM
    fi
}

function release() {
    local shard="$1"
    if [[ "$SHARDS_FROM_CONSUL" == "true" ]]; then
        CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" ENVIRONMENT="$ENVIRONMENT" DISPLAY="releases" SERVICE="signal" SHARD="$shard"  $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER
    else
        $LOCAL_PATH/shard.py --shard_release --environment $ENVIRONMENT --shard $SHARD
    fi
}

function core_provider() {
    local shard="$1"
    if [[ "$SHARDS_FROM_CONSUL" == "true" ]]; then
        PROVIDER=$(CONSUL_INCLUDE_AWS="$CONSUL_INCLUDE_AWS" CONSUL_INCLUDE_OCI="$CONSUL_INCLUDE_OCI" ENVIRONMENT="$ENVIRONMENT" DISPLAY="core_providers" SERVICE="signal" SHARD="$shard" $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER)
    fi

    if [ -z "$PROVIDER" ]; then
        local region=$(shard_region $shard)

        #pull in region-specific variables
        if [ -e "../all/regions/${region}.sh" ]; then
            PROVIDER="aws"
        else
            PROVIDER="oracle"
        fi
    fi

    echo $PROVIDER
}

function shard_region() {
    local shard="$1"
    SHARD_REGION=$($LOCAL_PATH/shard.py  --shard_region --environment=$ENVIRONMENT --shard=$SHARD)
    echo $SHARD_REGION
}

function shard_ip {
    local shard="$1"
    [ -z "$IP_TYPE" ] && IP_TYPE="external"

    local PROVIDER=$(core_provider $1)
    if [[ "$PROVIDER" == "oracle" ]]; then
        [ -z "$DNS_ZONE_NAME" ] && DNS_ZONE_NAME="$DEFAULT_DNS_ZONE_NAME"
        if [[ "$IP_TYPE" == "internal" ]]; then
            SHARD_HOST="$SHARD-internal.$DNS_ZONE_NAME"
        else
            SHARD_HOST="$SHARD.$DNS_ZONE_NAME"
        fi
        dig +short $SHARD_HOST
    fi
    if [[ "$PROVIDER" == "aws" ]]; then
        [ -z $EC2_REGION ] && EC2_REGION=$(shard_region $shard)
        if [[ "$IP_TYPE" == "external" ]]; then
            PUBLIC_FLAG="--public"
        else
            PUBLIC_FLAG=""
        fi
        $LOCAL_PATH/node.py --environment $ENVIRONMENT --shard $shard --role core --region $EC2_REGION --oracle --batch $PUBLIC_FLAG
    fi
}

function number() {
    echo $1 | rev | cut -d"-" -f1 | rev | tr -d '[:alpha:]'
}

function new() {
    local count="$1"
    local shard
    local shards=$(RELEASE_NUMBER="" list)
    local aws_shards=$($LOCAL_PATH/shard.py --list --environment=$ENVIRONMENT)
    local shard_numbers=()
    local found_numbers=()
    local found_count=0
    local check_shard=1

    for shard in $shards; do
        shard_numbers+=($(number $shard))
    done
    for shard in $aws_shards; do
        shard_numbers+=($(number $shard))
    done
    while [[ $found_count -lt $count ]]; do
        containsElement $check_shard "${shard_numbers[@]}"
        if [[ $? -eq 1 ]]; then
            # not in the list, so use it
            found_numbers+=($check_shard)
            shard_numbers+=($check_shard)
            found_count=$((found_count + 1))
        fi
        check_shard=$((check_shard+1))
    done
    echo "${found_numbers[@]}"
    # for n in $found_numbers; do
    #     echo $n
    # done
}

function containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}


case $ACTION in
    'shard_ip')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            shard_ip $SHARD $SHARD_IP_TYPE
        fi
        ;;
    'delete')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            delete $SHARD
        fi
        ;;
    'shard_region')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            shard_region $SHARD
        fi
        ;;
    'core_provider')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            core_provider $SHARD
        fi
        ;;
    'release')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            release $SHARD
        fi
        ;;
    'number')
        if [ -z "$SHARD" ]; then
            echo "No SHARD set, exiting..."
        else
            number $SHARD
        fi
        ;;
    'list')
        list
        ;;
    'list_releases')
        list_releases
        ;;
    'new')
        if [ -z "$COUNT" ]; then
            echo "No COUNT set, exiting..."
        else
            new $COUNT
        fi
        ;;
    *)
        echo "unknown action $ACTION"
        ;;
esac
