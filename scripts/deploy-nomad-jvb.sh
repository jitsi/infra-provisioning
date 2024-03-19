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

[ -z "$JVB_POOL_MODE" ] && export JVB_POOL_MODE="global"
[ -z "$SHARD_BASE" ] && SHARD_BASE="$ENVIRONMENT"

[ -z "$JVB_POOL_NAME" ] && JVB_POOL_NAME="$SHARD_BASE-$ORACLE_REGION-$JVB_POOL_MODE-$RELEASE_NUMBER"
if [ ! -z "$JVB_POOL_NAME" ]; then
  export SHARD=$JVB_POOL_NAME
  export SHARD_NAME=$SHARD
else
  echo "Error. JVB_POOL_NAME is empty"
  exit 213
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="JVB"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$JVB_VERSION" ]; then
    JVB_TAG="jvb-$JVB_VERSION-1"
    export CONFIG_jvb_version="$JVB_VERSION"
fi

[ -z "$JVB_TAG" ] && JVB_TAG="$DOCKER_TAG"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"
[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../ansible/secrets/asap-keys.yml"

ASAP_KEY_VARIABLE="asap_key_$ENVIRONMENT_TYPE"

JVB_XMPP_PASSWORD_VARIABLE="secrets_jvb_brewery_by_environment_A.\"$ENVIRONMENT\""

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export CONFIG_jvb_auth_password="$(ansible-vault view $ENCRYPTED_JVB_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JVB_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_asap_jwt_kid="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${ASAP_KEY_VARIABLE}.id" -)"

set -x
set +e

[ -z "$JVB_POOL_TYPE" ] && export CONFIG_jvb_pool_type="$JVB_POOL_TYPE"

export JOB_NAME="jvb-${SHARD}"
export NOMAD_URL="https://${ENVIRONMENT}-${ORACLE_REGION}-nomad.$TOP_LEVEL_DNS_ZONE_NAME"

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
export CONFIG_environment_type="${ENVIRONMENT_TYPE}"
export CONFIG_domain="$DOMAIN"
export CONFIG_shard="$SHARD"
export CONFIG_octo_region="$ORACLE_REGION"
# [ -n "$SHARD_STATE" ] && export CONFIG_shard_state="$SHARD_STATE"
export CONFIG_release_number="$RELEASE_NUMBER"
export CONFIG_jvb_version="$JVB_VERSION"
export CONFIG_pool_type="$NOMAD_POOL_TYPE"
export CONFIG_jvb_tag="$JVB_TAG"
export CONFIG_jvb_pool_mode="$JVB_POOL_MODE"

PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

nomad-pack render --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var "datacenter=$NOMAD_DC" \
  $PACKS_DIR/jitsi_meet_jvb > /tmp/input.hcl

nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var "datacenter=$NOMAD_DC" \
  $PACKS_DIR/jitsi_meet_jvb

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning JVB job, exiting"
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
  $PACKS_DIR/jitsi_meet_jvb

if [ $? -ne 0 ]; then
    echo "Failed to run JVB job, exiting"
    exit 5
else
    scripts/nomad-pack.sh status jitsi_meet_jvb --name "$JOB_NAME"
    if [ $? -ne 0 ]; then
        echo "Failed to get status for JVB job, exiting"
        exit 6
    fi
    echo "JVB deployment complete"
    exit 0
    # nomad-watch --out "deployment" started "$JOB_NAME"
    # WATCH_RET=$?
    # if [ $WATCH_RET -ne 0 ]; then
    #     echo "Failed starting job, dumping logs and exiting"
    #     nomad-watch started "$JOB_NAME"
    # fi
    # exit $WATCH_RET
fi
