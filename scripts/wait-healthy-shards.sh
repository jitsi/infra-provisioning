#!/bin/bash

#set -x

[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh ] && . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh

if [ -z "$SHARDS" ]; then
    echo "No SHARDS provided, exiting"
    exit 1
fi

# run as user
if [ -z "$1" ]; then
  SSH_USER=$(whoami)
  echo "Ansible SSH user is not defined. We use current user: $SSH_USER"
else
  SSH_USER=$1
  echo "Run ansible as $SSH_USER"
fi

# sleep between health checks
SLEEP_INTERVAL=60
# await a shard to become healthy for up to 20 mins
SLEEP_MAX=60*20

SHARD_IPS=()
FOUND_SHARDS=true

for SHARD in $SHARDS; do
      SHARD_CORE_PROVIDER="$(SHARD=$SHARD ENVIRONMENT=$ENVIRONMENT $LOCAL_PATH/shard.sh core_provider $ANSIBLE_SSH_USER)"
      if [ -z "$SHARD_CORE_PROVIDER" ]; then
        echo "No shard core provider found"
        FOUND_SHARDS=false
      else
        if [[ "$SHARD_CORE_PROVIDER" == "nomad" ]]; then
          SHARD_META="$(SHARD=$SHARD ENVIRONMENT=$ENVIRONMENT DISPLAY="service_meta" $LOCAL_PATH/consul-search.sh $SSH_USER | jq -r '.[0]')"
          SHARD_IPS+=( "$(echo "$SHARD_META" | jq -r '.signal_sidecar_http_ip')" )
          SHARD_CURL_IPS+=( "$(echo "$SHARD_META" | jq -r '.signal_sidecar_http_ip')" )
          SHARD_CURL_PORTS+=( "1$(echo "$SHARD_META" | jq -r '.signal_sidecar_http_port')" )
        else
          SHARD_IP="$(IP_TYPE="internal" SHARD=$SHARD ENVIRONMENT=$ENVIRONMENT $LOCAL_PATH/shard.sh shard_ip $SSH_USER)"
          if [ $? -eq 0 ]; then
            SHARD_IPS+=( "$SHARD_IP" )
            SHARD_CURL_IPS+=( "$SHARD_IP" )
            SHARD_CURL_PORTS+=( "6000" )
          else
            echo "No SHARD_IP found for $SHARD"
            FOUND_SHARDS=false
          fi
        fi
      fi
done
if $FOUND_SHARDS; then
  echo "found shard IPS: ${SHARD_CURL_IPS[@]}"
  END_LOOP="false"
  SLEEP_TOTAL=0
  FINAL_RET=0
  while [[ "$END_LOOP" == "false" ]]; do
    NEW_SHARD_IPS=()
    NEW_SHARD_PORTS=()
    for i in "${!SHARD_CURL_IPS[@]}"; do
      SHARD_CURL_IP="${SHARD_CURL_IPS[i]}"
      SHARD_CURL_PORT="${SHARD_CURL_PORTS[i]}"
      SIGNAL_REPORT=$(curl http://$SHARD_CURL_IP:$SHARD_CURL_PORT/signal/report)
      if [ $? -eq 0 ]; then
          SHARD_HEALTH="$(echo $SIGNAL_REPORT | jq  -r '.healthy')"
          if [[ "$SHARD_HEALTH" == "true" ]]; then
            echo "SHARD HEALTHY $SHARD_CURL_IP"
            # don't add to NEW_SHARD_IPS
          else
            NEW_SHARD_IPS+=( "$SHARD_CURL_IP" )
            NEW_SHARD_PORTS+=( "$SHARD_CURL_PORT" )
            echo "SHARD UNHEALTHY: $SHARD_CURL_IP:$SHARD_CURL_PORT $SIGNAL_REPORT"
          fi
      else
        NEW_SHARD_IPS+=( "$SHARD_CURL_IP" )
        NEW_SHARD_PORTS+=( "$SHARD_CURL_PORT" )
        echo "Failed to fetch signal report for $SHARD_CURL_IP:$SHARD_CURL_PORT $SIGNAL_REPORT"
      fi
    done
    if [[ ${#NEW_SHARD_IPS[@]} -eq 0 ]]; then
      echo "All shards healthy, exiting"
      FINAL_RET=0
      END_LOOP="true"
    else
      echo "At least one shard unhealthy, waiting on: ${NEW_SHARD_IPS[@]} ports ${NEW_SHARD_PORTS[@]}"
      SHARD_CURL_IPS=("${NEW_SHARD_IPS[@]}")
      SHARD_CURL_PORTS=("${NEW_SHARD_PORTS[@]}")
      sleep $SLEEP_INTERVAL
      SLEEP_TOTAL=$((SLEEP_TOTAL+SLEEP_INTERVAL))
      if [[ $SLEEP_TOTAL -gt $SLEEP_MAX ]]; then
        FINAL_RET=2
        # not really true but ends the loop
        END_LOOP="true"
      fi
    fi
  done
  exit $FINAL_RET
else
  echo "At least one shard not found, exiting"
  exit 2
fi
