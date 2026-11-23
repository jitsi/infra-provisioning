#!/bin/bash
set -e

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

if [ -z "$DOMAIN" ]; then
    echo "No DOMAIN set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_oracle_region="$ORACLE_REGION"
export NOMAD_VAR_domain="$DOMAIN"

# optional overrides
[ -n "$SYNTHETIC_TENANT" ] && export NOMAD_VAR_tenant="$SYNTHETIC_TENANT"
[ -n "$SYNTHETIC_PARTICIPANTS" ] && export NOMAD_VAR_participants="$SYNTHETIC_PARTICIPANTS"
[ -n "$SYNTHETIC_DURATION_SECONDS" ] && export NOMAD_VAR_conference_duration_seconds="$SYNTHETIC_DURATION_SECONDS"

JOB_NAME="cloudprober-synthetic-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/cloudprober-synthetic.hcl" | nomad job run -var="dc=$NOMAD_DC" -
exit $?
