#!/bin/bash

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$CLOUD_PROVIDER" ] && CLOUD_PROVIDER="oracle"

if [[ "$CLOUD_PROVIDER" == "nomad" ]]; then
    [ -z "$ENABLE_JVB_GLOBAL_POOLS" ] && ENABLE_JVB_GLOBAL_POOLS="true"
    [ -z "$ENABLE_JVB_LOCAL_POOLS" ] && ENABLE_JVB_LOCAL_POOLS="false"
    [ -z "$ENABLE_JVB_REMOTE_POOLS" ] && ENABLE_JVB_REMOTE_POOLS="false"
else
    [ -z "$ENABLE_JVB_GLOBAL_POOLS" ] && ENABLE_JVB_GLOBAL_POOLS="false"
    [ -z "$ENABLE_JVB_LOCAL_POOLS" ] && ENABLE_JVB_LOCAL_POOLS="false"
    [ -z "$ENABLE_JVB_REMOTE_POOLS" ] && ENABLE_JVB_REMOTE_POOLS="false"
fi

OUT=""

if [[ "$ENABLE_JVB_GLOBAL_POOLS" == "true" ]]; then
    OUT="global"
fi
if [[ "$ENABLE_JVB_LOCAL_POOLS" == "true" ]]; then
    OUT="local $OUT"
fi
if [[ "$ENABLE_JVB_REMOTE_POOLS" == "true" ]]; then
    OUT="remote $OUT"
fi

echo $OUT