#!/usr/bin/env bash
set -x

# IF THE CURRENT DIRECTORY HAS stack-env.sh THEN INCLUDE IT
[ -e ./stack-env.sh ] && . ./stack-env.sh

if [ -z "$ENVIRONMENT" ]; then
  echo "No ENVIRONMENT found. Exiting..."
  exit 2
fi

[ -e ./sites/$ENVIRONMENT/stack-env.sh ] && . ./sites/$ENVIRONMENT/stack-env.sh

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -z "$ORACLE_REGIONS" ] && ORACLE_REGIONS=$DRG_PEER_REGIONS

if [ -z "$ORACLE_REGIONS" ]; then
  echo "No ORACLE_REGIONS found. Exiting..."
  exit 2
fi

echo $ORACLE_REGIONS

for ORACLE_REGION in $ORACLE_REGIONS; do
  echo $ORACLE_REGION
  ENVIRONMENT=$ENVIRONMENT ORACLE_REGION=$ORACLE_REGION $LOCAL_PATH/create-waf-policies-oracle.sh
done
