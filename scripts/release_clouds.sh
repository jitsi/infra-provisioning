#!/bin/bash

HCV_ENVIRONMENT=$1
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# first pull cloud defaults
source $LOCAL_PATH/../clouds/all.sh

# next pull in environment overrides
STACKENV="$LOCAL_PATH/../sites/$HCV_ENVIRONMENT/stack-env.sh"

if [ -f "$STACKENV" ]; then
	source $STACKENV
fi

# output release clouds
echo $RELEASE_CLOUDS
