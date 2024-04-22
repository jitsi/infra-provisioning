#!/bin/bash
set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# Extract tenant ocid, SHAPE_2_4, SHAPE_1_4
. $LOCAL_PATH/../clouds/oracle.sh

# Input
#############################

# pull cloud defaults to get ORACLE_REGION
source $LOCAL_PATH/../clouds/all.sh

source $LOCAL_PATH/../clouds/$CLOUD_NAME.sh

source $LOCAL_PATH/../regions/$EC2_REGION.sh

[ -z "$HCV_ENVIRONMENT" ] && HCV_ENVIRONMENT=$ENVIRONMENT

if [ -z "$HCV_ENVIRONMENT" ]; then
  echo "No HCV_ENVIRONMENT found.  Exiting..."
  exit 1
fi

source $LOCAL_PATH/../sites/$HCV_ENVIRONMENT/stack-env.sh

# check regional settings for JVB pool sizes, use if found
REGION_JVB_POOL_SIZE_FILE="$LOCAL_PATH/../sites/$HCV_ENVIRONMENT/jvb-shard-sizes-by-region"

if [ -f "$REGION_JVB_POOL_SIZE_FILE" ]; then

  REGION_JVB_POOL_SIZE=$(cat $REGION_JVB_POOL_SIZE_FILE | grep $EC2_REGION | awk 'BEGIN { FS = "|" } ; {print $2}')
  [ ! -z "$REGION_JVB_POOL_SIZE" ] && DEFAULT_AUTOSCALER_JVB_POOL_SIZE="$REGION_JVB_POOL_SIZE"
fi

[ -z "$DEFAULT_AUTOSCALER_JVB_POOL_SIZE" ] && DEFAULT_AUTOSCALER_JVB_POOL_SIZE=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_A_1" ] && DEFAULT_INSTANCE_POOL_SIZE_A_1=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_E_5" ] && DEFAULT_INSTANCE_POOL_SIZE_E_5=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_E_4" ] && DEFAULT_INSTANCE_POOL_SIZE_E_4=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_E_3" ] && DEFAULT_INSTANCE_POOL_SIZE_E_3=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_2_4" ] && DEFAULT_INSTANCE_POOL_SIZE_2_4=2
[ -z "$DEFAULT_INSTANCE_POOL_SIZE_1_4" ] && DEFAULT_INSTANCE_POOL_SIZE_1_4=2

[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="$JVB_DEFAULT_AUTOSCALER_ENABLED"
[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="true"

if [ "$JVB_AUTOSCALER_ENABLED" == "true" ]; then
  [ -z "$INSTANCE_POOL_SIZE_A_1" ] && INSTANCE_POOL_SIZE_A_1="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
  [ -z "$INSTANCE_POOL_SIZE_E_5" ] && INSTANCE_POOL_SIZE_E_5="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
  [ -z "$INSTANCE_POOL_SIZE_E_4" ] && INSTANCE_POOL_SIZE_E_4="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
  [ -z "$INSTANCE_POOL_SIZE_E_3" ] && INSTANCE_POOL_SIZE_E_3="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
  [ -z "$INSTANCE_POOL_SIZE_2_4" ] && INSTANCE_POOL_SIZE_2_4="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
  [ -z "$INSTANCE_POOL_SIZE_1_4" ] && INSTANCE_POOL_SIZE_1_4="$DEFAULT_AUTOSCALER_JVB_POOL_SIZE"
else
  [ -z "$INSTANCE_POOL_SIZE_A_1" ] && INSTANCE_POOL_SIZE_A_1="$DEFAULT_INSTANCE_POOL_SIZE_A_1"
  [ -z "$INSTANCE_POOL_SIZE_E_5" ] && INSTANCE_POOL_SIZE_E_5="$DEFAULT_INSTANCE_POOL_SIZE_E_5"
  [ -z "$INSTANCE_POOL_SIZE_E_4" ] && INSTANCE_POOL_SIZE_E_4="$DEFAULT_INSTANCE_POOL_SIZE_E_4"
  [ -z "$INSTANCE_POOL_SIZE_E_3" ] && INSTANCE_POOL_SIZE_E_3="$DEFAULT_INSTANCE_POOL_SIZE_E_3"
  [ -z "$INSTANCE_POOL_SIZE_2_4" ] && INSTANCE_POOL_SIZE_2_4="$DEFAULT_INSTANCE_POOL_SIZE_2_4"
  [ -z "$INSTANCE_POOL_SIZE_1_4" ] && INSTANCE_POOL_SIZE_1_4="$DEFAULT_INSTANCE_POOL_SIZE_1_4"
fi

if [ -z "$SHARD_COUNT" ]; then
  echo "No SHARD_COUNT found.  Assuming 1 shard"
  SHARD_COUNT=1
fi

if [ -z "$ORACLE_REGION" ]; then
  echo "No ORACLE_REGION found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_A_1" ]; then
  echo "No INSTANCE_POOL_SIZE_A_1 found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_E_4" ]; then
  echo "No INSTANCE_POOL_SIZE_E_4 found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_E_5" ]; then
  echo "No INSTANCE_POOL_SIZE_E_5 found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_E_3" ]; then
  echo "No INSTANCE_POOL_SIZE_E_3 found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_2_4" ]; then
  echo "No INSTANCE_POOL_SIZE_2_4 found.  Exiting..."
  exit 1
fi

if [ -z "$INSTANCE_POOL_SIZE_1_4" ]; then
  echo "No INSTANCE_POOL_SIZE_1_4 found.  Exiting..."
  exit 1
fi

[ -z "$BUFFER_PERCENT" ] && export BUFFER_PERCENT=0


SHARD_PROPERTIES_FILE_ORACLE="./shard-properties-oracle.json"

# initialize final output file
echo '{}' >$SHARD_PROPERTIES_FILE_ORACLE

# Functions
#############################

GET_AVAILABLE_RETURN_VALUE=0
function get_available() {
  local shape=$1
  local availability_domains_in_region=$2

  local total_available=0
  local total=0

  local limit_name=""
  local shape_flex=false

  if [ "$shape" == "$SHAPE_A_1" ]; then
    limit_name="standard-a1-core-count"
    shape_flex=true
  elif [ "$shape" == "$SHAPE_E_5" ]; then
    limit_name="standard-e5-core-count"
    shape_flex=true
  elif [ "$shape" == "$SHAPE_E_4" ]; then
    limit_name="standard-e4-core-count"
    shape_flex=true
  elif [ "$shape" == "$SHAPE_E_3" ]; then
    limit_name="standard-e3-core-ad-count"
    shape_flex=true
  elif [ "$shape" == "$SHAPE_2_4" ]; then
    limit_name="vm-standard2-4-count"
  elif [ "$shape" == "$SHAPE_1_4" ]; then
    limit_name="vm-standard1-4-count"
  else
    #error unknown type
    return 1
  fi
  # Availability in ADs is not always equal, but the JVB instance pool will use all ADs
  # Cap AD available instances to the min of all ADs
  local min_available_in_ad=-1
  local ads_count=0
  for AD in $availability_domains_in_region; do
    ads_count=$((ads_count + 1))
    limits_json=$(oci limits resource-availability get --compartment-id=$TENANCY_OCID --region=$ORACLE_REGION --limit-name=$limit_name --service-name=compute --availability-domain=$AD)
    available_in_ad=$(echo $limits_json | jq -r .data.available)
    used_in_ad=$(echo $limits_json | jq -r .data.used)

    if $shape_flex; then
      [ -z "$OCPUS" ] && OCPUS=4
      #round down available and round up used values by OCPU to get total instances
      available_in_ad=$(echo $available_in_ad | awk "{print \$1/$OCPUS}" | awk '{print int($1-0.5)}')
      used_in_ad=$(echo $used_in_ad | awk "{print \$1/$OCPUS}" | awk '{print int($1+0.5)}')
    fi

    if [ $min_available_in_ad -lt 0 ] || [ $available_in_ad -lt $min_available_in_ad ]; then
      min_available_in_ad=$available_in_ad
    fi

    ((total = total + available_in_ad))
    ((total = total + used_in_ad))
  done

  total_available=$((min_available_in_ad * ads_count))

  # Always keep a percent of total instances unused
  buffer=$(($BUFFER_PERCENT * total))
  buffer=$(($buffer / 100))

  GET_AVAILABLE_RETURN_VALUE=$(($total_available - $buffer))
  if (($GET_AVAILABLE_RETURN_VALUE < 0)); then
    GET_AVAILABLE_RETURN_VALUE=0
  fi

  # success
  return 0
}

# Get available shard count for each shape
###########################################

AVAILABLE_SHARD_COUNT_2_4=0
AVAILABLE_SHARD_COUNT_1_4=0

AVAILABILITY_DOMAINS_IN_REGION=($(oci iam availability-domain list --region=$ORACLE_REGION | jq .data[].name | jq --slurp 'join(" ")' | jq -r .))

if [[ $ORACLE_REGION == 'eu-frankfurt-1' ]]; then
  AVAILABILITY_DOMAINS_SHAPE_A_1=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_5=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_4=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_3=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_2_4=("${AVAILABILITY_DOMAINS_IN_REGION[0]}" "${AVAILABILITY_DOMAINS_IN_REGION[1]}")
  AVAILABILITY_DOMAINS_SHAPE_1_4=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
else
  AVAILABILITY_DOMAINS_SHAPE_A_1=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_5=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_4=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_E_3=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_2_4=("${AVAILABILITY_DOMAINS_IN_REGION[@]}")
  AVAILABILITY_DOMAINS_SHAPE_1_4=()
fi

#TODO add retries for get_available and for get availability domains
if [[ ${#AVAILABILITY_DOMAINS_SHAPE_A_1[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_A_1 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_A_1[@]})"
  AVAILABLE_SHARD_COUNT_A_1=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_A_1))
else
  AVAILABLE_SHARD_COUNT_A_1=0
fi

if [[ ${#AVAILABILITY_DOMAINS_SHAPE_E_5[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_E_5 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_E_5[@]})"
  AVAILABLE_SHARD_COUNT_E_5=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_E_5))
else
  AVAILABLE_SHARD_COUNT_E_5=0
fi

if [[ ${#AVAILABILITY_DOMAINS_SHAPE_E_4[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_E_4 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_E_4[@]})"
  AVAILABLE_SHARD_COUNT_E_4=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_E_4))
else
  AVAILABLE_SHARD_COUNT_E_4=0
fi

#TODO add retries for get_available and for get availability domains
if [[ ${#AVAILABILITY_DOMAINS_SHAPE_E_3[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_E_3 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_E_3[@]})"
  AVAILABLE_SHARD_COUNT_E_3=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_E_3))
else
  AVAILABLE_SHARD_COUNT_E_3=0
fi


if [[ ${#AVAILABILITY_DOMAINS_SHAPE_2_4[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_2_4 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_2_4[@]})"
  AVAILABLE_SHARD_COUNT_2_4=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_2_4))
else
  AVAILABLE_SHARD_COUNT_2_4=0
fi

if [[ ${#AVAILABILITY_DOMAINS_SHAPE_1_4[@]} -gt 0 ]]; then
  GET_AVAILABLE_RETURN_VALUE=0
  get_available $SHAPE_1_4 "$(echo ${AVAILABILITY_DOMAINS_SHAPE_1_4[@]})"
  AVAILABLE_SHARD_COUNT_1_4=$(($GET_AVAILABLE_RETURN_VALUE / $INSTANCE_POOL_SIZE_1_4))
else
  AVAILABLE_SHARD_COUNT_1_4=0
fi

# Split shards per shape; Consume first the 2.4 shape unless e.3 enabled is set
######################################################
[ "$ENABLE_A_1" == "true" ] || AVAILABLE_SHARD_COUNT_A_1=0

[ "$ENABLE_E_5" == "true" ] || AVAILABLE_SHARD_COUNT_E_5=0

[ "$ENABLE_E_4" == "true" ] || AVAILABLE_SHARD_COUNT_E_4=0

[ "$ENABLE_E_3" == "true" ] || AVAILABLE_SHARD_COUNT_E_3=0


SHARD_COUNT_SHAPE_A_1=0
SHARD_COUNT_SHAPE_E_5=0
SHARD_COUNT_SHAPE_E_4=0
SHARD_COUNT_SHAPE_E_3=0
SHARD_COUNT_SHAPE_2_4=0
SHARD_COUNT_SHAPE_1_4=0
SHARD_COUNT_TO_PROCESS=$SHARD_COUNT


if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_A_1)); then
  SHARD_COUNT_SHAPE_A_1=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_A_1=$AVAILABLE_SHARD_COUNT_A_1
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_A_1))

if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_E_5)); then
  SHARD_COUNT_SHAPE_E_5=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_E_5=$AVAILABLE_SHARD_COUNT_E_5
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_E_5))

if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_E_4)); then
  SHARD_COUNT_SHAPE_E_4=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_E_4=$AVAILABLE_SHARD_COUNT_E_4
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_E_4))

if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_E_3)); then
  SHARD_COUNT_SHAPE_E_3=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_E_3=$AVAILABLE_SHARD_COUNT_E_3
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_E_3))

if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_2_4)); then
  SHARD_COUNT_SHAPE_2_4=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_2_4=$AVAILABLE_SHARD_COUNT_2_4
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_2_4))

if (($SHARD_COUNT_TO_PROCESS <= $AVAILABLE_SHARD_COUNT_1_4)); then
  SHARD_COUNT_SHAPE_1_4=$SHARD_COUNT_TO_PROCESS
else
  SHARD_COUNT_SHAPE_1_4=$AVAILABLE_SHARD_COUNT_1_4
fi
SHARD_COUNT_TO_PROCESS=$(($SHARD_COUNT_TO_PROCESS - $SHARD_COUNT_SHAPE_1_4))

# Output
#####################

OUT_SHARD_COUNT_SHAPE_A_1=$SHARD_COUNT_SHAPE_A_1
OUT_SHARD_COUNT_SHAPE_E_5=$SHARD_COUNT_SHAPE_E_5
OUT_SHARD_COUNT_SHAPE_E_4=$SHARD_COUNT_SHAPE_E_4
OUT_SHARD_COUNT_SHAPE_E_3=$SHARD_COUNT_SHAPE_E_3
OUT_SHARD_COUNT_SHAPE_2_4=$SHARD_COUNT_SHAPE_2_4
OUT_SHARD_COUNT_SHAPE_1_4=$SHARD_COUNT_SHAPE_1_4
OUT_SHARD_COUNT_UNPROCESSED=$SHARD_COUNT_TO_PROCESS
# Output ADs as json array, the format expected by create-jvb-stack-oracle.sh
OUT_AVAILABILITY_DOMAINS_SHAPE_A_1=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_A_1[@]} | jq -R . | jq -s .)
OUT_AVAILABILITY_DOMAINS_SHAPE_E_5=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_E_5[@]} | jq -R . | jq -s .)
OUT_AVAILABILITY_DOMAINS_SHAPE_E_4=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_E_4[@]} | jq -R . | jq -s .)
OUT_AVAILABILITY_DOMAINS_SHAPE_E_3=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_E_3[@]} | jq -R . | jq -s .)
OUT_AVAILABILITY_DOMAINS_SHAPE_2_4=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_2_4[@]} | jq -R . | jq -s .)
OUT_AVAILABILITY_DOMAINS_SHAPE_1_4=$(printf '%s\n' ${AVAILABILITY_DOMAINS_SHAPE_1_4[@]} | jq -R . | jq -s .)

# This is for debugging purposes
echo "OUT_SHARD_COUNT_SHAPE_A_1=$SHARD_COUNT_SHAPE_A_1"
echo "OUT_SHARD_COUNT_SHAPE_E_5=$SHARD_COUNT_SHAPE_E_5"
echo "OUT_SHARD_COUNT_SHAPE_E_4=$SHARD_COUNT_SHAPE_E_4"
echo "OUT_SHARD_COUNT_SHAPE_E_3=$SHARD_COUNT_SHAPE_E_3"
echo "OUT_SHARD_COUNT_SHAPE_2_4=$SHARD_COUNT_SHAPE_2_4"
echo "OUT_SHARD_COUNT_SHAPE_1_4=$SHARD_COUNT_SHAPE_1_4"
echo "OUT_SHARD_COUNT_UNPROCESSED=$OUT_SHARD_COUNT_UNPROCESSED"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_A_1=$OUT_AVAILABILITY_DOMAINS_SHAPE_A_1"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_E_5=$OUT_AVAILABILITY_DOMAINS_SHAPE_E_5"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_E_4=$OUT_AVAILABILITY_DOMAINS_SHAPE_E_4"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_E_3=$OUT_AVAILABILITY_DOMAINS_SHAPE_E_3"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_2_4=$OUT_AVAILABILITY_DOMAINS_SHAPE_2_4"
echo "OUT_AVAILABILITY_DOMAINS_SHAPE_1_4=$OUT_AVAILABILITY_DOMAINS_SHAPE_1_4"
echo "OUT_SHARD_POOL_SIZE_2_4=$INSTANCE_POOL_SIZE_2_4"
echo "OUT_SHARD_POOL_SIZE_1_4=$INSTANCE_POOL_SIZE_1_4"
echo "JVB_AUTOSCALER_ENABLED=$JVB_AUTOSCALER_ENABLED"

SHARD_JSON="{\"OUT_SHARD_COUNT_SHAPE_E_4\": \"$OUT_SHARD_COUNT_SHAPE_E_4\",
\"OUT_SHARD_COUNT_SHAPE_E_5\": \"$OUT_SHARD_COUNT_SHAPE_E_5\",
\"OUT_SHARD_COUNT_SHAPE_A_1\": \"$OUT_SHARD_COUNT_SHAPE_A_1\",
\"OUT_SHARD_COUNT_SHAPE_E_3\": \"$OUT_SHARD_COUNT_SHAPE_E_3\",
\"OUT_SHARD_COUNT_SHAPE_2_4\": \"$OUT_SHARD_COUNT_SHAPE_2_4\",
\"OUT_SHARD_COUNT_SHAPE_1_4\": \"$OUT_SHARD_COUNT_SHAPE_1_4\",
\"OUT_SHARD_COUNT_UNPROCESSED\": \"$OUT_SHARD_COUNT_UNPROCESSED\",
\"OUT_AVAILABILITY_DOMAINS_SHAPE_A_1\": $OUT_AVAILABILITY_DOMAINS_SHAPE_A_1,
\"OUT_AVAILABILITY_DOMAINS_SHAPE_E_5\": $OUT_AVAILABILITY_DOMAINS_SHAPE_E_5,
\"OUT_AVAILABILITY_DOMAINS_SHAPE_E_4\": $OUT_AVAILABILITY_DOMAINS_SHAPE_E_4,
\"OUT_AVAILABILITY_DOMAINS_SHAPE_E_3\": $OUT_AVAILABILITY_DOMAINS_SHAPE_E_3,
\"OUT_AVAILABILITY_DOMAINS_SHAPE_2_4\": $OUT_AVAILABILITY_DOMAINS_SHAPE_2_4,
\"OUT_AVAILABILITY_DOMAINS_SHAPE_1_4\": $OUT_AVAILABILITY_DOMAINS_SHAPE_1_4,
\"OUT_SHARD_POOL_SIZE_A_1\": $INSTANCE_POOL_SIZE_A_1,
\"OUT_SHARD_POOL_SIZE_E_5\": $INSTANCE_POOL_SIZE_E_5,
\"OUT_SHARD_POOL_SIZE_E_4\": $INSTANCE_POOL_SIZE_E_4,
\"OUT_SHARD_POOL_SIZE_E_3\": $INSTANCE_POOL_SIZE_E_3,
\"OUT_SHARD_POOL_SIZE_2_4\": $INSTANCE_POOL_SIZE_2_4,
\"OUT_SHARD_POOL_SIZE_1_4\": $INSTANCE_POOL_SIZE_1_4,
\"OUT_JVB_AUTOSCALER_ENABLED\": $JVB_AUTOSCALER_ENABLED
}"
echo "$SHARD_JSON" > $SHARD_PROPERTIES_FILE_ORACLE

if [[ $OUT_SHARD_COUNT_UNPROCESSED -ge 1 ]]; then
  echo "Error. Not enough Oracle instances left to deploy the amount of Oracle JVB instance pools"
  echo "There is space only for $OUT_SHARD_COUNT_SHAPE_A_1 shards/pools of shape $SHAPE_A_1 and size $INSTANCE_POOL_SIZE_A_1, $OUT_SHARD_COUNT_SHAPE_E_5 shards/pools of shape $SHAPE_E_5  and size $INSTANCE_POOL_SIZE_E_5, $OUT_SHARD_COUNT_SHAPE_E_4 shards/pools of shape $SHAPE_E_4 and size $INSTANCE_POOL_SIZE_E_4, $OUT_SHARD_COUNT_SHAPE_E_3 shards/pools of shape $SHAPE_E_3 and size $INSTANCE_POOL_SIZE_E_3, as well as $OUT_SHARD_COUNT_SHAPE_2_4 shards/pools of shape $SHAPE_2_4 and size $INSTANCE_POOL_SIZE_2_4, as well as $OUT_SHARD_COUNT_SHAPE_1_4 shards/pools of shape $SHAPE_1_4 and size $INSTANCE_POOL_SIZE_1_4"
  exit 2
fi
