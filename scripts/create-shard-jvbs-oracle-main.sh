#!/bin/bash
set -x

# This script is run directly from Jenkins job

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 203
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="$JVB_DEFAULT_AUTOSCALER_ENABLED"
[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="true"

if [ "$JVB_AUTOSCALER_ENABLED" == "true" ]; then
  scripts/create-shard-custom-jvbs-oracle.sh
else
  scripts/create-shard-jvbs-oracle.sh
fi

exit $?