#!/bin/bash
if [  -z "$1" ]
then
  ANSIBLE_SSH_USER=$(whoami)
else
  ANSIBLE_SSH_USER=$1
fi

set -x

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$SHARD_DEFAULT_COUNT_AWS" ] && SHARD_DEFAULT_COUNT_AWS=1
[ -z "$SHARD_DEFAULT_COUNT_ORACLE" ] && SHARD_DEFAULT_COUNT_ORACLE=0

#Look for JVB counts by region in current directory
SHARD_COUNT_FILE_AWS="./sites/$ENVIRONMENT/shards-by-region-aws"
SHARD_COUNT_FILE_ORACLE="./sites/$ENVIRONMENT/shards-by-region-oracle"

ADD_SHARD_COUNT_FILE_AWS="./add-shards-by-cloud-aws"
ADD_SHARD_COUNT_FILE_ORACLE="./add-shards-by-cloud-oracle"
ADD_SHARD_COUNT_AWS_JSON_FILE="./add-shards-by-cloud-aws.json"
ADD_SHARD_COUNT_ORACLE_JSON_FILE="./add-shards-by-cloud-oracle.json"

# initialize final output file
echo '{}' > $ADD_SHARD_COUNT_AWS_JSON_FILE
echo '{}' > $ADD_SHARD_COUNT_ORACLE_JSON_FILE

TOTAL_NEW_SHARDS=0

# clear existing add file if not already removed
[ -f "$ADD_SHARD_COUNT_FILE_AWS" ] && rm $ADD_SHARD_COUNT_FILE_AWS
[ -f "$ADD_SHARD_COUNT_FILE_ORACLE" ] && rm $ADD_SHARD_COUNT_FILE_ORACLE

if [ -z "$RELEASE_NUMBER" ]; then
    echo "No RELEASE_NUMBER provided, exiting..."
    exit 1
fi

if [ -z "$CLOUDS" ]; then
    CLOUDS=$($LOCAL_PATH/release_clouds.sh $ENVIRONMENT)
fi

TOTAL_NEW_SHARDS=0

# loop through clouds, find matching shards
for CLOUD in $CLOUDS; do
    . $LOCAL_PATH/../clouds/$CLOUD.sh

    # deprecated, to be removed: expand shards with AWS JVBs
    # SHARDS=$(INCLUDE_AWS="true" INCLUDE_OCI="false" CLOUD_NAME="$CLOUD" RELEASE_NUMBER="$RELEASE_NUMBER" ENVIRONMENT="$ENVIRONMENT" ../all/bin/cloud_shards.sh $ANSIBLE_SSH_USER)
    # SHARD_COUNT=$(echo $SHARDS | wc -w)
    # DESIRED_COUNT=$SHARD_DEFAULT_COUNT_AWS
    # if [ -f "$SHARD_COUNT_FILE_AWS" ]; then
    #     # check if JVB count by region is defined, if so use it
    #     REGION_SHARD_COUNT=$(cat $SHARD_COUNT_FILE_AWS | grep $EC2_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
    #     [ ! -z "$REGION_SHARD_COUNT" ] && DESIRED_COUNT="$REGION_SHARD_COUNT"
    # fi

    # ADD_COUNT=$((DESIRED_COUNT - SHARD_COUNT))
    # if (( $ADD_COUNT > 0 )); then
    #     # add this many new shards for the region
    #     echo "$CLOUD $ADD_COUNT" >> $ADD_SHARD_COUNT_FILE_AWS
    #     TOTAL_NEW_SHARDS=$((TOTAL_NEW_SHARDS + ADD_COUNT))
    # fi

    # now find all shards with oracle provider
    SHARDS=$(CLOUD_NAME="$CLOUD" RELEASE_NUMBER="$RELEASE_NUMBER" ENVIRONMENT="$ENVIRONMENT" $LOCAL_PATH/cloud_shards.sh $ANSIBLE_SSH_USER)
    SHARD_COUNT=$(echo $SHARDS | wc -w)
    DESIRED_COUNT=$SHARD_DEFAULT_COUNT_ORACLE
    if [ -f "$SHARD_COUNT_FILE_ORACLE" ]; then
        # check if JVB count by region is defined, if so use it
        REGION_SHARD_COUNT=$(cat $SHARD_COUNT_FILE_ORACLE | grep $EC2_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
        [ ! -z "$REGION_SHARD_COUNT" ] && DESIRED_COUNT="$REGION_SHARD_COUNT"
    fi

    ADD_COUNT=$((DESIRED_COUNT - SHARD_COUNT))
    if (( $ADD_COUNT > 0 )); then
        # add this many new shards for the region
        echo "$CLOUD $ADD_COUNT" >> $ADD_SHARD_COUNT_FILE_ORACLE
        TOTAL_NEW_SHARDS=$((TOTAL_NEW_SHARDS + ADD_COUNT))
    fi
done

if (( $TOTAL_NEW_SHARDS > 0 )); then
    # done detecting how many shards to add, now generate shard numbers
    SHARD_NUMBERS=( $(ENVIRONMENT="$ENVIRONMENT" COUNT=$TOTAL_NEW_SHARDS $LOCAL_PATH/shard.sh new $ANSIBLE_SSH_USER) )

    POS=0
    cat $ADD_SHARD_COUNT_FILE_AWS | while read CLOUD_NAME SHARD_COUNT; do
        CLOUD_SHARD_NUMBERS=${SHARD_NUMBERS[@]:$POS:$SHARD_COUNT}
        POS=$((POS+SHARD_COUNT))
        CLOUD_JSON="{\"$CLOUD_NAME\": \"${CLOUD_SHARD_NUMBERS[@]}\"}"
        echo $CLOUD_JSON > './cloud-shards-tmp.json'
        cp $ADD_SHARD_COUNT_AWS_JSON_FILE ./cloud-shards-tmp2.json
        jq -s ".[0] * .[1]" ./cloud-shards-tmp.json ./cloud-shards-tmp2.json > $ADD_SHARD_COUNT_AWS_JSON_FILE
    done

    cat $ADD_SHARD_COUNT_FILE_ORACLE | while read CLOUD_NAME SHARD_COUNT; do
        CLOUD_SHARD_NUMBERS=${SHARD_NUMBERS[@]:$POS:$SHARD_COUNT}
        POS=$((POS+SHARD_COUNT))
        CLOUD_JSON="{\"$CLOUD_NAME\": \"${CLOUD_SHARD_NUMBERS[@]}\"}"
        echo $CLOUD_JSON > './cloud-shards-tmp.json'
        cp $ADD_SHARD_COUNT_ORACLE_JSON_FILE ./cloud-shards-tmp2.json
        jq -s ".[0] * .[1]" ./cloud-shards-tmp.json ./cloud-shards-tmp2.json > $ADD_SHARD_COUNT_ORACLE_JSON_FILE
    done

    [ -f "./cloud-shards-tmp2.json" ] && rm ./cloud-shards-tmp2.json
    [ -f "./cloud-shards-tmp.json" ] && rm ./cloud-shards-tmp.json
fi