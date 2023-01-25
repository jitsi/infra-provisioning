#!/bin/bash

# master script to set a region to drain or ready

[ -z "$REGION_STATE" ] && REGION_STATE=$1

if [ -z "$REGION_STATE" ]; then
    echo "REGION STATE not set or passed as first parameter, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$CLOUD_NAME" ]; then
	if [ ! -z "$REGION" ]; then
    	. $LOCAL_PATH/../regions/$REGION.sh
        [ -z "$REGION_ALIAS" ] && REGION_ALIAS="$REGION"
    	CLOUD_NAME="$REGION_ALIAS-peer1"
    fi
fi

if [ -z "$CLOUD_NAME" ]; then
    echo "CLOUD_NAME not set, exiting"
    exit 2
fi

export CLOUD_NAME

# first set the global accelerator settings
$LOCAL_PATH/set-global-accelerator-state.sh $REGION_STATE

FINAL_RET=0

ARET=$?

if [ $ARET -eq 0 ]; then
    echo "Success in global accelerator"
else
    echo "Failure in global accelerator"
    FINAL_RET=2
fi

# next set ipv6 record state
$LOCAL_PATH/set-region-ipv6-record-state.sh $REGION_STATE
IRET=$?

if [ $IRET -eq 0 ]; then
    echo "Success in route53"
else
    echo "Failure in route53"
    FINAL_RET=3
fi


# TODO: eventually add optionally drain or ready the shards

echo "Make sure you set all shards in the region to $REGION_STATE as well"
exit $FINAL_RET
