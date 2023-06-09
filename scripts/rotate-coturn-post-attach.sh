#!/bin/bash

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# re-run coturn nomad deploy for region to ensure containers are up on new nodes
if [[ "$NOMAD_COTURN_FLAG" == "true" ]]; then
    $LOCAL_PATH/deploy-nomad-coturn.sh
fi

GOOD_PORT=443
WAIT_GOOD=120
# assumes pre attach ran
if [ ! -z "$COTURN_HEALTHCHECK_ID" ]; then
    echo "health check found $COTURN_HEALTHCHECK_ID"
    echo "Updating health check $COTURN_HEALTHCHECK_ID back to correct port $GOOD_PORT to allow DNS to be advertised again"
    aws route53 update-health-check --health-check-id $COTURN_HEALTHCHECK_ID --port $GOOD_PORT
    echo "Waiting $WAIT_GOOD seconds for health intervals to be healthy so DNS is published again"
    sleep $WAIT_GOOD
else
    echo "No health check set, something went wrong with detach of $INSTANCE_ID"
fi