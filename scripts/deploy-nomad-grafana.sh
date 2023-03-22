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

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$GRAFANA_HOSTNAME" ] && GRAFANA_HOSTNAME="$ENVIRONMENT-grafana.$TOP_LEVEL_DNS_ZONE_NAME"

export NOMAD_VAR_grafana_hostname="$GRAFANA_HOSTNAME"

sed -e "s/\[JOB_NAME\]/$DOMAIN/" "$NOMAD_JOB_PATH/grafana.hcl" | nomad job run -var="dc=$NOMAD_DC" -
