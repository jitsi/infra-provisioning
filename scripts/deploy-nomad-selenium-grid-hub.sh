#!/bin/bash

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

if [ -z "$GRID" ]; then
    echo "No GRID set, exiting"
    exit 2
fi

[ -z "$PUBLIC_GRID" ] && PUBLIC_GRID="false"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

INTERNAL_SUFFIX="-internal"
if [[ "$PUBLIC_GRID" == "true" ]]; then
    export NOMAD_VAR_service_tag_urlprefix=""
    INTERNAL_SUFFIX=""
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
JOB_NAME="grid-hub-$GRID"
export NOMAD_VAR_grid="$GRID"

# Resolve selenium grid version: env var > Docker Hub lookup > HCL default
if [ -n "$SELENIUM_GRID_HUB_VERSION" ]; then
    export NOMAD_VAR_selenium_version="$SELENIUM_GRID_HUB_VERSION"
    echo "Using provided selenium version: $SELENIUM_GRID_HUB_VERSION"
else
    echo "Looking up latest selenium/hub version from Docker Hub..."
    SELENIUM_HUB_VERSION=$(curl -s --connect-timeout 10 --max-time 30 \
        "https://hub.docker.com/v2/repositories/selenium/hub/tags/?page_size=100&ordering=last_updated" \
        | jq -r '[.results[].name | select(test("^[0-9]+\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | last')
    if [ -n "$SELENIUM_HUB_VERSION" ] && [ "$SELENIUM_HUB_VERSION" != "null" ]; then
        export NOMAD_VAR_selenium_version="$SELENIUM_HUB_VERSION"
        echo "Resolved latest selenium version from Docker Hub: $SELENIUM_HUB_VERSION"
    else
        echo "WARNING: Failed to resolve selenium version from Docker Hub, falling back to HCL default"
    fi
fi

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/selenium-grid-hub.hcl" | nomad job run -var="dc=$NOMAD_DC" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad selenium grid hub job, exiting"
    exit 5
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-${GRID}-grid"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general${INTERNAL_SUFFIX}.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
