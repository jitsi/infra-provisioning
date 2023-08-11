#!/usr/bin/env bash

# builds haproxy.inventory for an enviroment
# takes an optional argument that causes the rebuild to only happen
# if $1 ms have passed

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

export HAPROXY_CACHE="./haproxy.inventory"
echo "## haproxy-buildcache: exported HAPROXY_CACHE=${HAPROXY_CACHE}"

if [ "$SKIP_BUILD_CACHE" == "true" ]; then
    echo "## haproxy-buildcache: skipped due to SKIP_BUILD_CACHE flag"
fi

CACHE_TTL=$CACHE_TTL

# if a TTL was sent , skip rebuilding if the cache is fresh
if [ ! -z "$CACHE_TTL" ] && [ "$SKIP_BUILD_CACHE" != "true" ]; then
    if [ -e $HAPROXY_CACHE ]; then
        CURTIME=$(date +%s)

        if [[ $(uname) == "Darwin" ]]; then
            FILETIME=$(stat -t %s $HAPROXY_CACHE | awk '{print $9}' | tr -d '"')
        else
            FILETIME=$(stat $HAPROXY_CACHE -c %Y)
        fi

        TIMEDIFF=$(expr $CURTIME - $FILETIME)
        if [ ! $TIMEDIFF -gt $CACHE_TTL ]; then
            echo "## skipping haproxy-buildcache; cache is fresh enough"
            SKIP_BUILD_CACHE="true"
        fi
    fi
fi

if [ "$SKIP_BUILD_CACHE" != "true" ]; then
    # build the cache
    PROXIES="$(SERVICE="haproxy" DISPLAY="addresses" $LOCAL_PATH/consul-search.sh ubuntu)"

    if [ $? == 0 ] && [ ! -z "$PROXIES" ]; then
        echo "## haproxy-buildcache: building ${HAPROXY_CACHE}"
        echo '[tag_shard_role_haproxy]' > $HAPROXY_CACHE; 
        for PROXY in $PROXIES; do
            echo $PROXY >> $HAPROXY_CACHE;
        done
    else
        if [ ! -e $HAPROXY_CACHE ]; then
            echo "## WARNING: haproxy-buildcache: failed to discover nodes; falling back to an existing cache file at ${HAPROXY_CACHE}"
        else
            echo "## ERROR: haproxy-buildcache: failed to discover nodes and no previous cache available; exiting"
            exit 1
        fi
    fi
fi
