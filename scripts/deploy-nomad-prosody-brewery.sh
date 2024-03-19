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

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="general"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$PROSODY_VERSION" ]; then
    [ -z "$PROSODY_TAG" ] && PROSODY_TAG="prosody-$PROSODY_VERSION"
fi

[ -z "$JICOFO_TAG" ] && JICOFO_TAG="$DOCKER_TAG"
[ -z "$PROSODY_TAG" ] && PROSODY_TAG="$DOCKER_TAG"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENCRYPTED_JIBRI_CREDENTIALS_FILE" ] && ENCRYPTED_JIBRI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jibri.yml"
[ -z "$ENCRYPTED_JICOFO_CREDENTIALS_FILE" ] && ENCRYPTED_JICOFO_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jicofo.yml"
[ -z "$ENCRYPTED_JIGASI_CREDENTIALS_FILE" ] && ENCRYPTED_JIGASI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jigasi.yml"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

JVB_XMPP_PASSWORD_VARIABLE="secrets_jvb_brewery_by_environment_A.\"$ENVIRONMENT\""
JIBRI_XMPP_PASSWORD_VARIABLE="jibri_auth_password"
JIBRI_RECORDER_PASSWORD_VARIABLE="jibri_selenium_auth_password"
JIGASI_XMPP_PASSWORD_VARIABLE="jigasi_xmpp_password"
JICOFO_XMPP_PASSWORD_VARIABLE="secrets_jicofo_focus_by_environment.\"$ENVIRONMENT\""

SIP_JIBRI_SHARED_SECRET_VARIABLE="sip_jibri_shared_secrets.\"$ENVIRONMENT\""

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export CONFIG_jvb_auth_password="$(ansible-vault view $ENCRYPTED_JVB_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JVB_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_jibri_xmpp_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_jibri_recorder_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_RECORDER_PASSWORD_VARIABLE}" -)"
export CONFIG_jigasi_xmpp_password="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_XMPP_PASSWORD_VARIABLE}" -)"
# TODO: use the separate _jvb and _visitor secrets for the different accounts.
export CONFIG_jicofo_auth_password="$(ansible-vault view $ENCRYPTED_JICOFO_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE  | yq eval .${JICOFO_XMPP_PASSWORD_VARIABLE} -)"

export CONFIG_jigasi_shared_secret="$CONFIG_jigasi_xmpp_password"

SIP_JIBRI_SHARED_SECRET="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIP_JIBRI_SHARED_SECRET_VARIABLE}" -)"
if [[ "$SIP_JIBRI_SHARED_SECRET" != "null" ]]; then
    export CONFIG_sip_jibri_shared_secret="$SIP_JIBRI_SHARED_SECRET"
fi

set -x
set +e

export CONFIG_environment_type="${ENVIRONMENT_TYPE}"

function yamltoenv() {
    # set -x
    local yaml_file=$1
    # evaluate each integer and boolean in the environment configuration file and export it as a CONFIG_ environment variable
    eval $(yq '.. | select((tag == "!!int" or tag == "!!bool") and (path|length)==1) |  "export CONFIG_"+(path | join("_")) + "=\"" + . + "\""' $yaml_file)

    # hack due to yq inability to escape a single backslash
    # https://github.com/mikefarah/yq/issues/1692
    export BACKSLASH='\'

    # evaluate each string in the environment configuration file and export it as a CONFIG_ environment variable
    eval $(yq '.. | select(tag == "!!str" and (path|length)==1) |  "export CONFIG_"+(path | join("_")) + "=\"" + (. | sub("\n"," ") | sub("\"",strenv(BACKSLASH)+"\"")) + "\""' $yaml_file)
    # set +x
}

yamltoenv $MAIN_CONFIGURATION_FILE
yamltoenv $ENVIRONMENT_CONFIGURATION_FILE

export CONFIG_environment="$ENVIRONMENT"
export CONFIG_domain="$DOMAIN"
export CONFIG_octo_region="$ORACLE_REGION"
export CONFIG_prosody_tag="$PROSODY_TAG"
export CONFIG_pool_type="$NOMAD_POOL_TYPE"

if [ -z "$CONFIG_force_pull" ]; then
    if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
        export CONFIG_force_pull="false"
    else
        export CONFIG_force_pull="true"
    fi
fi

export JOB_NAME="prosody-brewery-${ORACLE_REGION}"

PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"


nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var "datacenter=$NOMAD_DC" \
  $PACKS_DIR/prosody_brewery

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning prosody brewery job, exiting"
    exit 4
else
    if [ $PLAN_RET -eq 1 ]; then
        echo "Plan was successful, will make changes"
    fi
    if [ $PLAN_RET -eq 0 ]; then
        echo "Plan was successful, no changes needed"
    fi
fi

nomad-pack run --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var "datacenter=$NOMAD_DC" \
  $PACKS_DIR/prosody_brewery

if [ $? -ne 0 ]; then
    echo "Failed to run prosody brewery job, exiting"
    exit 5
else
    scripts/nomad-pack.sh status prosody_brewery --name "$JOB_NAME"
    if [ $? -ne 0 ]; then
        echo "Failed to get status for prosody brewery job, exiting"
        exit 6
    fi
    nomad-watch --out "deploy" started "$JOB_NAME"
    WATCH_RET=$?
    if [ $WATCH_RET -ne 0 ]; then
        echo "Failed starting job, dumping logs and exiting"
        nomad-watch started "$JOB_NAME"
    fi
    exit $WATCH_RET
fi
