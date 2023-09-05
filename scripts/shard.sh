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

function inventory() {
    DISPLAY=addresses $LOCAL_PATH/consul-search.sh $ANSIBLE_SSH_USER
}

function shard_ip {
    local shard="$1"
    [ -z "$IP_TYPE" ] && IP_TYPE="external"

    local PROVIDER=$(core_provider $1)
    if [[ "$PROVIDER" == "nomad" ]]; then
        # nomad shards aren't ansible-able to don't do anything
        echo ''
    fi

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

function shard_name() {
    [ -z "$SHARD_BASE" ] && SHARD_BASE=$ENVIRONMENT

    NUMBER=$1
    PROVIDER=$2

    SHARD_NAME=''
    case $PROVIDER in
        'oracle'):
            if [ -z "$ORACLE_REGION" ]; then
                echo "No ORACLE_REGION set, exiting..."
                return 1
            else
                SHARD_NAME="${SHARD_BASE}-${ORACLE_REGION}-s${NUMBER}"
            fi
            ;;
        'nomad'):
            if [ -z "$ORACLE_REGION" ]; then
                echo "No ORACLE_REGION set, exiting..."
                return 1
            else
                SHARD_NAME="${SHARD_BASE}-${ORACLE_REGION}-s${NUMBER}"
            fi
            ;;
        'aws'):
            [ -z "$REGION_ALIAS" ] && REGION_ALIAS=$EC2_REGION
            [ -z "$JVB_AZ_LETTER1" ] && JVB_AZ_LETTER1="a"
            [ -z "$JVB_AZ_LETTER2" ] && JVB_AZ_LETTER2="b"
            if [ $((SHARD_NUMBER%2)) -eq 0 ]; then
                #even shard number goes in the 1st AZ (us-east-1a)
                JVB_AZ="${JVB_AZ_REGION}${JVB_AZ_LETTER1}"
            else
                #odd shard number goes in the 2nd AZ (us-east-1b)
                JVB_AZ="${JVB_AZ_REGION}${JVB_AZ_LETTER2}"
            fi
            JVB_AZ_LETTER="${JVB_AZ: -1}"

            if [ -z "$REGION_ALIAS" ]; then
                echo "No REGION_ALIAS set, exiting..."
                return 1
            else
                SHARD_NAME="${SHARD_BASE}-${REGION_ALIAS}${JVB_AZ_LETTER}-s${NUMBER}"
            fi
            ;;
    esac
    if [ -n "$SHARD_NAME" ]; then
        echo $SHARD_NAME
        return 0
    fi
    return 1
}

case $ACTION in
    'name')
        if [ -z "$SHARD_NUMBER" ]; then
            echo "No SHARD_NUMBER set, exiting..."
        else
            shard_name $SHARD_NUMBER $CORE_CLOUD_PROVIDER
        fi
        ;;
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
    'inventory')
        inventory
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
