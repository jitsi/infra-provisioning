
#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -e "./stack-env.sh" ]; then 
    . ./stack-env.sh
else
    if [ ! -z "$ENVIRONMENT" ]; then
        . $LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh
    fi
fi

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION found.  Exiting..."
    exit 203
fi

. $LOCAL_PATH/../clouds/all.sh
. $LOCAL_PATH/../clouds/oracle.sh

[ -z "$DEFAULT_DNS_ZONE_NAME" ] && DEFAULT_DNS_ZONE_NAME="oracle.infra.jitsi.net"

#set -x

JOB=$1
SEARCH=$2


function log_search() {
    local job="$1"
    local search="$2"
    local region="$3"
    set -x
    [ -z "$SEARCH_PERIOD" ] && SEARCH_PERIOD="1h"
    LOKI_ADDR="https://${ENVIRONMENT}-${region}-loki.${TOP_LEVEL_DNS_ZONE_NAME}"
    logcli query -q --addr $LOKI_ADDR \
        --output=jsonl \
        --since="$SEARCH_PERIOD" \
    "{job=\"$job\"} |~ \"(?i)$search\"" | jq -r -s '.[]|"\(.timestamp): \(.labels.task) \(.line|fromjson|.message)"'
}

log_search $JOB $SEARCH $ORACLE_REGION