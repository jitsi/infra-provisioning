#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="fabio-$ORACLE_REGION"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/fabio.hcl" | nomad job run -var="dc=$NOMAD_DC" -

NOMAD_EXIT_CODE=$?

if [ $NOMAD_EXIT_CODE -eq 0 ]; then
    echo "Fabio deployment completed successfully"
    exit 0
fi

# If nomad job run failed, check actual job status
# For system jobs with updates, "failed to place" during evaluation can occur
# even when the rolling update succeeds
echo "Nomad job run exited with code $NOMAD_EXIT_CODE, checking final job status..."
sleep 2
NOMAD_STATUS=$(nomad job status $JOB_NAME 2>&1)

if echo "$NOMAD_STATUS" | grep -q "Status.*=.*running"; then
    RUNNING_ALLOCS=$(echo "$NOMAD_STATUS" | awk '/^fabio/{print $4}')
    echo "Fabio deployment successful - $RUNNING_ALLOCS allocations running"
    exit 0
else
    echo "Fabio deployment failed - job not in running state"
    echo "$NOMAD_STATUS"
    exit 5
fi
