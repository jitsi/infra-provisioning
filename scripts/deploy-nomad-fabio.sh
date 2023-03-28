#!/bin/bash

set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -z "$REGIONS" ] && REGIONS="$DRG_PEER_REGIONS"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="[]"
for ORACLE_REGION in $REGIONS; do
    NOMAD_DC="$( echo "$NOMAD_DC" "[\"$ENVIRONMENT-$ORACLE_REGION\"]" | jq -c -s '.|add')"
done

export NOMAD_VAR_dc="$NOMAD_DC"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/fabio.hcl" | nomad job run -
