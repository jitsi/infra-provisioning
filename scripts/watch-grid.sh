#!/bin/bash


ctrl_c() {
  echo "** Trapped CTRL-C **"
  # Perform cleanup or other actions here
  cat $MAX_FILE | jq -s 'add|group_by(.browser,.version)|map(max_by(.count))'
  exit 0
}

trap ctrl_c INT

[ -z "$GRID_NAME" ] && GRID_NAME="validocker"
[ -z "$MAX_FILE" ] && MAX_FILE="./$GRID_NAME-max-sessions"


[ -f "$MAX_FILE" ] && rm $MAX_FILE

# input is a count of browser and version used in the grid like {"browser": "chrome", "version": "133.01", "count": 1}
while true; do
    curl -X POST -H "Content-Type: application/json" --data '{"query":"{ sessionsInfo { sessions { id, capabilities } } }"}' -s https://torture-test-us-phoenix-1-${GRID_NAME}-grid.jitsi.net/graphql | \
    jq '.data.sessionsInfo.sessions|map(.capabilities|fromjson|{"browser": .browserName, "version":.browserVersion})|group_by(.browser,.version)|map({"browser": .[0].browser, "version":.[0].version, count: length})' | tee -a $MAX_FILE
    sleep 1
done
