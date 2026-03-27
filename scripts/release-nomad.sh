#!/bin/bash
# Deploy a Nomad service to all regions in an environment.
#
# Usage:
#   ENVIRONMENT=<env> SERVICE_NAME=<service> ./scripts/release-nomad.sh
#
# Optionally limit to specific regions:
#   ENVIRONMENT=prod-8x8 SERVICE_NAME=scry NOMAD_REGIONS="us-ashburn-1 eu-frankfurt-1" ./scripts/release-nomad.sh

set -e

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

if [ -z "$SERVICE_NAME" ]; then
    echo "No SERVICE_NAME set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# Search infra-provisioning/scripts first, then infra-provisioning/scripts-custom
if [ -f "$LOCAL_PATH/deploy-nomad-${SERVICE_NAME}.sh" ]; then
    DEPLOY_SCRIPT="$LOCAL_PATH/deploy-nomad-${SERVICE_NAME}.sh"
elif [ -f "$LOCAL_PATH/../scripts-custom/deploy-nomad-${SERVICE_NAME}.sh" ]; then
    DEPLOY_SCRIPT="$LOCAL_PATH/../scripts-custom/deploy-nomad-${SERVICE_NAME}.sh"
else
    echo "Deploy script not found for service: $SERVICE_NAME"
    echo "Searched:"
    echo "  $LOCAL_PATH/deploy-nomad-${SERVICE_NAME}.sh"
    echo "  $LOCAL_PATH/../scripts-custom/deploy-nomad-${SERVICE_NAME}.sh"
    exit 2
fi

STACK_ENV="$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"
if [ ! -f "$STACK_ENV" ]; then
    echo "No stack-env.sh found for environment: $ENVIRONMENT"
    exit 2
fi

# Load NOMAD_REGIONS from stack-env.sh if not already set
if [ -z "$NOMAD_REGIONS" ]; then
    . "$STACK_ENV"
fi

if [ -z "$NOMAD_REGIONS" ]; then
    echo "NOMAD_REGIONS is not set in $STACK_ENV"
    exit 2
fi

echo "Releasing $SERVICE_NAME to $ENVIRONMENT in regions: $NOMAD_REGIONS"
echo ""

for REGION in $NOMAD_REGIONS; do
    echo "=== Deploying to $ENVIRONMENT / $REGION ==="
    if ENVIRONMENT="$ENVIRONMENT" ORACLE_REGION="$REGION" "$DEPLOY_SCRIPT"; then
        echo "=== $REGION: OK ==="
    else
        echo "=== $REGION: FAILED ==="
        echo "Aborting release."
        exit 1
    fi
    echo ""
done

echo "Release of $SERVICE_NAME to $ENVIRONMENT complete."
