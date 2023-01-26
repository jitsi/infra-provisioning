#!/bin/bash
set -x

# This script is run directly from Jenkins job

#IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh


if [ -z "$ENVIRONMENT" ]; then
   echo "No ENVIRONMENT provided or found.  Exiting ..."
   exit 201
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="$JVB_DEFAULT_AUTOSCALER_ENABLED"
[ -z "$JVB_AUTOSCALER_ENABLED" ] && JVB_AUTOSCALER_ENABLED="true"

if [ "$JVB_AUTOSCALER_ENABLED" == "true" ]; then
  export DESIRED_COUNT="$INSTANCE_POOL_SIZE"
  export MIN_DESIRED="$AUTOSCALER_POOL_MIN_SIZE"
  $LOCAL_PATH/scale-jvbs-custom-autoscaler-oracle.sh
else
  $LOCAL_PATH/scale-jvbs-oracle.sh
fi

exit $?
