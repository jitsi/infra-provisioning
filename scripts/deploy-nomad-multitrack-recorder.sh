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

[ -z "$JMR_AWS_REGION" ] && JMR_AWS_REGION="$(grep "ORACLE_REGION=\"$ORACLE_REGION\"" $LOCAL_PATH/../regions/* | cut -d ':' -f1 | grep -o '[^/]*$'| cut -d'.' -f1)"

if [ -z "$JMR_AWS_REGION" ]; then
    echo "No JMR_AWS_REGION set or found, exiting"
    exit 2
fi
export NOMAD_VAR_aws_region="$JMR_AWS_REGION"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$ENCRYPTED_NOMAD_FILE" ] && ENCRYPTED_NOMAD_FILE="$LOCAL_PATH/../ansible/secrets/nomad.yml"
set +x
set -e
set -o pipefail
export NOMAD_VAR_oracle_s3_credentials="$(ansible-vault view $ENCRYPTED_NOMAD_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".nomad_s3fs_credentials" -)"

set -x

if [ -z "$JMR_QUEUE_ID" ]; then
    JMR_QUEUE="$(oci queue queue-admin queue list --all --compartment-id $COMPARTMENT_OCID --region $ORACLE_REGION --output json | jq -r '.data.items[]|select(."display-name"=="multitrack-recorder-'$ENVIRONMENT'")')"
    JMR_QUEUE_ID="$(echo "$JMR_QUEUE" | jq -r '.id')"
    [[ "$JMR_QUEUE_ID" == "null" ]] && JMR_QUEUE_ID=""
    JMR_QUEUE_ENDPOINT="$(echo "$JMR_QUEUE" | jq -r '."messages-endpoint"')"
    [[ "$JMR_QUEUE_ENDPOINT" == "null" ]] && JMR_QUEUE_ENDPOINT=""
fi
if [ -z "$JMR_QUEUE_ID" ]; then
    echo "No JMR_QUEUE_ID set or found in region $ORACLE_REGION compartment $COMPARTMENT_OCID, exiting"
    exit 2
fi
if [ -z "$JMR_QUEUE_ENDPOINT" ]; then
    echo "No JMR_QUEUE_ENDPOINT set or found in region $ORACLE_REGION compartment $COMPARTMENT_OCID, exiting"
    exit 2
fi
NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_queue_id="$JMR_QUEUE_ID"
export NOMAD_VAR_queue_endpoint="$JMR_QUEUE_ENDPOINT"

# defaults to latest
[ -n "$APP_VERSION" ] && export NOMAD_VAR_app_version="$APP_VERSION"
JOB_NAME="multitrack-recorder-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/multitrack-recorder.hcl" | nomad job run -var="dc=$NOMAD_DC" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad loki job, exiting"
    exit 5
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-jmr"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
$LOCAL_PATH/create-oracle-cname-stack.sh

# AWS alias
export UNIQUE_ID="${ENVIRONMENT}-${JMR_AWS_REGION}"
export CNAME_VALUE="${UNIQUE_ID}-jmr"
export STACK_NAME="${UNIQUE_ID}-jmr-cname"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
$LOCAL_PATH/create-oracle-cname-stack.sh
