#!/bin/bash

# master script to set a region to drain or ready

if [ -z "$CF_AUTH_EMAIL" ] || [ -z "$CF_AUTH_KEY" ]; then
    if [ -f /etc/jitsi/cloudflare.env ]; then 
        . /etc/jitsi/cloudflare.env
    else
        echo "WARNING: Config not found at /etc/jitsi/cloudflare.env and environment variables (CF_AUTH_KEY CF_AUTH_EMAIL) not set"
    fi
fi

[ -z "$POOL_STATE" ] && POOL_STATE=$1

if [ -z "$ACCOUNT_ID" ]; then
    echo "No ACCOUNT_ID set, exiting"
    exit 1
fi

if [ -z "$POOL" ]; then
    echo "No POOL set, exiting"
    exit 2
fi

if [ -z "$CF_AUTH_EMAIL" ]; then
    echo "No CF_AUTH_EMAIL set, exiting"
    exit 3
fi

if [ -z "$CF_AUTH_KEY" ]; then
    echo "No CF_AUTH_KEY set, exiting"
    exit 4
fi


if [ -z "$POOL_STATE" ]; then
    echo "No POOL_STATE set, exiting"
    exit 2
fi

if [[ "$POOL_STATE" == "ready" ]]; then
    SHED_VALUE=0
fi
if [[ "$POOL_STATE" == "drain" ]]; then
    SHED_VALUE=100
fi

echo "Setting pool $POOL in $ACCOUNT_ID to $POOL_STATE"

curl -v -X PATCH -H "X-Auth-Email: $CF_AUTH_EMAIL" -H "X-Auth-Key: $CF_AUTH_KEY" -H "Content-Type: application/json" \
    -d "{\"load_shedding\":{\"default_policy\":\"hash\",\"default_percent\":$SHED_VALUE, \"session_percent\": $SHED_VALUE}}" \
    "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/load_balancers/pools/$POOL"