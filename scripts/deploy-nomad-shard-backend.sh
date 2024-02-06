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

if [ -z "$SHARD" ]; then
    echo "No SHARD set, exiting"
    exit 2
fi

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$SIGNAL_API_HOSTNAME" ] && SIGNAL_API_HOSTNAME="signal-api-$ENVIRONMENT.$TOP_LEVEL_DNS_ZONE_NAME"

[ -z "$NOMAD_POOL_TYPE" ] && NOMAD_POOL_TYPE="general"

[ -z "$DOCKER_TAG" ] && DOCKER_TAG="unstable-$(date +%Y-%m-%d)"

if [ -n "$SIGNAL_VERSION" ]; then
    if [ -z "$JICOFO_VERSION" ]; then
        JICOFO_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f1)"
    fi
    if [ -z "$JITSI_MEET_VERSION" ]; then
        JITSI_MEET_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f2)"
    fi
    if [ -z "$PROSODY_VERSION" ]; then
        PROSODY_VERSION="$(echo $SIGNAL_VERSION | cut -d'-' -f3)"
    fi
else
    if [ -n "$JICOFO_VERSION" ]; then
        SIGNAL_VERSION="$JICOFO_VERSION-$JITSI_MEET_VERSION-$PROSODY_VERSION"
    else
        SIGNAL_VERSION="$DOCKER_TAG"
    fi
fi

if [ -n "$JICOFO_VERSION" ]; then
    [ -z "$JICOFO_TAG" ] && JICOFO_TAG="jicofo-1.0-$JICOFO_VERSION-1"
fi

if [ -n "$PROSODY_VERSION" ]; then
    [ -z "$PROSODY_TAG" ] && PROSODY_TAG="prosody-$PROSODY_VERSION"
fi


[ -z "$JICOFO_TAG" ] && JICOFO_TAG="$DOCKER_TAG"
[ -z "$PROSODY_TAG" ] && PROSODY_TAG="$DOCKER_TAG"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="stage"

[ -z "$ENCRYPTED_JVB_CREDENTIALS_FILE" ] && ENCRYPTED_JVB_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jvb.yml"
[ -z "$ENCRYPTED_JIBRI_CREDENTIALS_FILE" ] && ENCRYPTED_JIBRI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jibri.yml"
[ -z "$ENCRYPTED_JIGASI_CREDENTIALS_FILE" ] && ENCRYPTED_JIGASI_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/jigasi.yml"
[ -z "$ENCRYPTED_COTURN_CREDENTIALS_FILE" ] && ENCRYPTED_COTURN_CREDENTIALS_FILE="$LOCAL_PATH/../ansible/secrets/coturn.yml"
[ -z "$ENCRYPTED_ASAP_KEYS_FILE" ] && ENCRYPTED_ASAP_KEYS_FILE="$LOCAL_PATH/../ansible/secrets/asap-keys.yml"
[ -z "$ENCRYPTED_PROSODY_EGRESS_AWS_FILE" ] && ENCRYPTED_PROSODY_EGRESS_AWS_FILE="$LOCAL_PATH/../ansible/secrets/prosody-egress-aws.yml"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"
[ -z "$MAIN_CONFIGURATION_FILE" ] && MAIN_CONFIGURATION_FILE="$LOCAL_PATH/../config/vars.yml"

JVB_XMPP_PASSWORD_VARIABLE="jvb_xmpp_password"
JIBRI_XMPP_PASSWORD_VARIABLE="jibri_auth_password"
JIBRI_RECORDER_PASSWORD_VARIABLE="jibri_selenium_auth_password"
JIGASI_XMPP_PASSWORD_VARIABLE="jigasi_xmpp_password"
JICOFO_XMPP_PASSWORD_VARIABLE="prosody_focus_user_secret"

JWT_ASAP_KEYSERVER_VARIABLE="prosody_public_key_repo_url"
JWT_ACCEPTED_ISSUERS_VARIABLE="prosody_asap_accepted_issuers"
JWT_ACCEPTED_AUDIENCES_VARIABLE="prosody_asap_accepted_audiences"
TURNRELAY_HOST_VARIABLE="prosody_mod_turncredentials_hosts"
TURNRELAY_PASSWORD_VARIABLE="coturn_secret"
ASAP_KEY_VARIABLE="asap_key_$ENVIRONMENT_TYPE"

SIP_JIBRI_SHARED_SECRET_VARIABLE="sip_jibri_shared_secrets.\"$ENVIRONMENT\""

# ensure no output for ansible vault contents and fail if ansible-vault fails
set +x
set -e
set -o pipefail
export CONFIG_jvb_auth_password="$(ansible-vault view $ENCRYPTED_JVB_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JVB_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_jibri_xmpp_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_jibri_recorder_password="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIBRI_RECORDER_PASSWORD_VARIABLE}" -)"
export CONFIG_jigasi_xmpp_password="$(ansible-vault view $ENCRYPTED_JIGASI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${JIGASI_XMPP_PASSWORD_VARIABLE}" -)"
export CONFIG_turnrelay_password="$(ansible-vault view $ENCRYPTED_COTURN_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${TURNRELAY_PASSWORD_VARIABLE}" -)"

export CONFIG_jicofo_auth_password="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${JICOFO_XMPP_PASSWORD_VARIABLE} -)"

export CONFIG_asap_jwt_kid="$(ansible-vault view $ENCRYPTED_ASAP_KEYS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${ASAP_KEY_VARIABLE}.id" -)"

export CONFIG_aws_access_key_id="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_access_key_id_by_type.$ENVIRONMENT_TYPE" -)"
export CONFIG_aws_secret_access_key="$(ansible-vault view $ENCRYPTED_PROSODY_EGRESS_AWS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".prosody_egress_aws_secret_access_key_by_type.$ENVIRONMENT_TYPE" -)"

export CONFIG_jigasi_shared_secret="$CONFIG_jigasi_xmpp_password"

SIP_JIBRI_SHARED_SECRET="$(ansible-vault view $ENCRYPTED_JIBRI_CREDENTIALS_FILE --vault-password $VAULT_PASSWORD_FILE | yq eval ".${SIP_JIBRI_SHARED_SECRET_VARIABLE}" -)"
if [[ "$SIP_JIBRI_SHARED_SECRET" != "null" ]]; then
    export CONFIG_sip_jibri_shared_secret="$SIP_JIBRI_SHARED_SECRET"
fi

set -x
set +e

export CONFIG_environment_type="${ENVIRONMENT_TYPE}"

TURNRELAY_HOST_ARRAY="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
if [[ "$TURNRELAY_HOST_ARRAY" == "null" ]]; then
    TURNRELAY_HOST_ARRAY="$(cat $MAIN_CONFIGURATION_FILE | yq eval .${TURNRELAY_HOST_VARIABLE} -)"
fi

if [[ "$TURNRELAY_HOST_ARRAY" != "null" ]]; then
    export CONFIG_turnrelay_host="$(echo $TURNRELAY_HOST_ARRAY | yq eval '.[0]' -)"
fi

export CONFIG_jwt_accepted_issuers="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_ISSUERS_VARIABLE} | @csv" -)"
export CONFIG_jwt_accepted_audiences="$(cat $MAIN_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_AUDIENCES_VARIABLE} | @csv" -)"

JWT_ACCEPTED_ISSUERS_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_ISSUERS_VARIABLE} | @csv" -)"
if [[ "$JWT_ACCEPTED_ISSUERS_ENV" != "null" ]]; then
    export CONFIG_jwt_accepted_issuers="$JWT_ACCEPTED_ISSUERS_ENV"
fi

JWT_ACCEPTED_AUDIENCES_ENV="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".${JWT_ACCEPTED_AUDIENCES_VARIABLE} | @csv" -)"
if [[ "$JWT_ACCEPTED_AUDIENCES_ENV" != "null" ]]; then
    export CONFIG_jwt_accepted_audiences="$JWT_ACCEPTED_AUDIENCES_ENV"
fi

PROSODY_MUC_MODERATED_ROOMS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".prosody_muc_moderated_rooms | @csv" -)"
if [ -n "$PROSODY_MUC_MODERATED_ROOMS" ]; then
    if [[ "$PROSODY_MUC_MODERATED_ROOMS" != "null" ]]; then
        export CONFIG_muc_moderated_rooms="$PROSODY_MUC_MODERATED_ROOMS"
    fi
fi

PROSODY_MUC_MODERATED_SUBDOMAINS="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".prosody_muc_moderated_subdomains | @csv" -)"
if [ -n "$PROSODY_MUC_MODERATED_SUBDOMAINS" ]; then
    if [[ "$PROSODY_MUC_MODERATED_SUBDOMAINS" != "null" ]]; then
        export CONFIG_muc_moderated_subdomains="$PROSODY_MUC_MODERATED_SUBDOMAINS"
    fi
fi

# check main configuration file for rate limit whitelist
export PROSODY_RATE_LIMIT_ALLOW_RANGES="$(cat $MAIN_CONFIGURATION_FILE | yq eval '.prosody_rate_limit_whitelist| @csv' -)"
if [ -n "$PROSODY_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$PROSODY_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export CONFIG_prosody_rate_limit_allow_ranges="$PROSODY_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

# check environment configuration file for rate limit whitelist
export PROSODY_RATE_LIMIT_ALLOW_RANGES="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.prosody_rate_limit_whitelist | @csv' -)"
if [ -n "$PROSODY_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$PROSODY_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export CONFIG_prosody_rate_limit_allow_ranges="$PROSODY_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

# check main configuration file for nginx rate limit whitelist
export NGINX_RATE_LIMIT_ALLOW_RANGES="$(cat $MAIN_CONFIGURATION_FILE | yq eval '.nginx_rate_limit_whitelist| @csv' -)"
if [ -n "$NGINX_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$NGINX_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export CONFIG_nginx_rate_limit_whitelist="$NGINX_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

# check environment configuration file for nginx rate limit whitelist
export NGINX_RATE_LIMIT_ALLOW_RANGES="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval '.nginx_rate_limit_whitelist | @csv' -)"
if [ -n "$NGINX_RATE_LIMIT_ALLOW_RANGES" ]; then
    if [[ "$NGINX_RATE_LIMIT_ALLOW_RANGES" != "null" ]]; then
        export CONFIG_nginx_rate_limit_whitelist="$NGINX_RATE_LIMIT_ALLOW_RANGES"
    fi
fi

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
export CONFIG_shard="$SHARD"
export CONFIG_shard_id="$(echo $SHARD| rev | cut -d"-" -f1 | rev | tr -d '[:alpha:]')"
export CONFIG_octo_region="$ORACLE_REGION"
export CONFIG_release_number="$RELEASE_NUMBER"
export CONFIG_signal_version="$SIGNAL_VERSION"
export CONFIG_jicofo_tag="$JICOFO_TAG"
export CONFIG_prosody_tag="$PROSODY_TAG"
export CONFIG_pool_type="$NOMAD_POOL_TYPE"
export CONFIG_signal_api_hostname="$SIGNAL_API_HOSTNAME"

[ -z "$CONFIG_visitors_count" ] && CONFIG_visitors_count=0
[ -z "$CONFIG_visitors_count" ] && CONFIG_visitors_count=0
[ -z "$CONFIG_nomad_enable_fabio_domain" ] && CONFIG_nomad_enable_fabio_domain="false"

if [ -z "$CONFIG_force_pull" ]; then
    if [[ "$ENVIRONMENT_TYPE" == "prod" ]]; then
        export CONFIG_force_pull="false"
    else
        export CONFIG_force_pull="true"
    fi
fi

[ -n "$SHARD_BREWERY_ENABLED" ] && export CONFIG_prosody_brewery_shard_enabled="$SHARD_BREWERY_ENABLED"

export JOB_NAME="shard-${SHARD}"

PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"


nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var "datacenter=$NOMAD_DC" \
  -var "visitors_count=$CONFIG_visitors_count" \
  -var "fabio_domain_enabled=$CONFIG_nomad_enable_fabio_domain" \
  $PACKS_DIR/jitsi_meet_backend

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning shard backend job, exiting"
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
  -var "visitors_count=$CONFIG_visitors_count" \
  -var "fabio_domain_enabled=$CONFIG_nomad_enable_fabio_domain" \
  $PACKS_DIR/jitsi_meet_backend

if [ $? -ne 0 ]; then
    echo "Failed to run shard backend job, exiting"
    exit 5
else
    scripts/nomad-pack.sh status jitsi_meet_backend --name "$JOB_NAME"
    if [ $? -ne 0 ]; then
        echo "Failed to get status for shard backend job, exiting"
        exit 6
    fi
    nomad-watch --out "deployment" started "$JOB_NAME"
    WATCH_RET=$?
    if [ $WATCH_RET -ne 0 ]; then
        echo "Failed starting job, dumping logs and exiting"
        nomad-watch started "$JOB_NAME"
    fi
    exit $WATCH_RET
fi
