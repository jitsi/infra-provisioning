
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

if [ -z "$JOB" ]; then
    echo "Not enough parameters provided, exiting.."
    exit 5
fi
if [ -z "$SEARCH" ]; then
    echo "Not enough parameters provided, exiting.."
    exit 6
fi


function log_search() {
    local job="$1"
    local search="$2"
    local region="$3"
    set -x

    # from and to date need to be exactly like '2024-01-06T00:00:00.999999999-06:00'
    [ -z "$SEARCH_PERIOD" ] && SEARCH_PERIOD="1h"
    [ -z "$SEARCH_LIMIT" ] && SEARCH_LIMIT="30"
    [ -n "$SEARCH_FROM" ] && FROM_PARAM="--from $SEARCH_FROM"
    [ -n "$SEARCH_TO" ] && TO_PARAM="--to $SEARCH_TO"
    if [ -n "$FROM_PARAM" ]; then
        SEARCH_PARAM="$FROM_PARAM $TO_PARAM"
    else
        SEARCH_PARAM="--since=$SEARCH_PERIOD"
    fi
    [ -z "$SEARCH_LIMIT" ] && SEARCH_LIMIT="1000"
    LOKI_ADDR="https://${ENVIRONMENT}-${region}-loki.${TOP_LEVEL_DNS_ZONE_NAME}"
    logcli query -q --addr $LOKI_ADDR \
        --output=jsonl \
        --limit=$SEARCH_LIMIT \
        $SEARCH_PARAM \
    "{job=\"$job\"} |~ \"(?i)$search\"" | jq -r -s '.[]|"\(.timestamp): \(.labels.task) \(.line|fromjson|.message)"'
}

log_search $JOB $SEARCH $ORACLE_REGION