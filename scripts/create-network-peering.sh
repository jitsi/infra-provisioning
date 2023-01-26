#!/bin/bash
set +x #echo on

export ENABLE_VPC_PEERING=true
export VPC_PEERING_STATUS_TAG=$ENABLE_VPC_PEERING

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

#load cloud defaults
[ -e $LOCAL_PATH/../clouds/all.sh ] && . $LOCAL_PATH/../clouds/all.sh

PEERING_CLOUDS=()

export DEFAULT_CLOUD_PREFIX="peer1"

for region in ${DEFAULT_BUILD_REGIONS[@]} ; do
    unset REGION_ALIAS
    unset CF_TEMPLATE_JSON

    source ../all/regions/${region}.sh
    
    [ -z $REGION_ALIAS ] && REGION_ALIAS=$EC2_REGION
    
    export CLOUD_NAME="$REGION_ALIAS-${DEFAULT_CLOUD_PREFIX}"
    export CF_TEMPLATE_JSON="/tmp/${REGION_ALIAS}-${DEFAULT_CLOUD_PREFIX}-vaas-network-tmp.template.json"
    
    if [ ! -e $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh ];then
        continue
    fi

    PEERING_CLOUDS+=($CLOUD_NAME)

    ( yes | ./create-network-stack.sh ) &

done
wait

if [[ ${#PEERING_CLOUDS[@]} -le 1 ]]; then
    echo 'Peering clouds do not exist.Exit.'
    exit 1
fi

for peering_cloud in ${PEERING_CLOUDS[@]} ; do
    
    echo ${PEERING_CLOUDS[@]}
    
    arr_for_delete=($peering_cloud)
    
    CLOUD_NAME=$peering_cloud
   
    ( 
        . $LOCAL_PATH/../clouds/${CLOUD_NAME}.sh
        $LOCAL_PATH/create_network_vpc_peering.py --region $EC2_REGION -dr $DEFAULT_BUILD_REGIONS -cp ${DEFAULT_CLOUD_PREFIX}

    )
    
    PEERING_CLOUDS=("${PEERING_CLOUDS[@]/$arr_for_delete}")

done
