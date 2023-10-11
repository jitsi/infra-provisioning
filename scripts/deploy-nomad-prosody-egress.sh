#!/bin/bash
set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"


[ -z "$ENCRYPTED_PROSODY_EGRESS_AWS_FILE" ] && ENCRYPTED_PROSODY_EGRESS_AWS_FILE="$LOCAL_PATH/../ansible/secrets/prosody-egress-aws.yml"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="dev"

# use dev profile for stage envs
[[ "$ENVIRONMENT_TYPE" == "stage" ]] && ENVIRONMENT_TYPE="dev"

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export NOMAD_VAR_aws_access_key_id="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_access_key_id_by_type.$ENVIRONMENT_TYPE" -)"
export NOMAD_VAR_aws_secret_access_key="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_secret_access_key_by_type.$ENVIRONMENT_TYPE" -)"

set -x

export NOMAD_VAR_environment_type="${ENVIRONMENT_TYPE}"


[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

export NOMAD_VAR_environment="$ENVIRONMENT"
export NOMAD_VAR_domain="$DOMAIN"
export NOMAD_VAR_octo_region="$ORACLE_REGION"

JOB_NAME="prosodyegress-$ORACLE_REGION"
export NOMAD_VAR_dc="$NOMAD_DC"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/prosody-egress.hcl" | nomad job run -
