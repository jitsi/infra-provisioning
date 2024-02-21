#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

set -x

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"
[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

if [ -z "$DOMAIN" ]; then
    echo "No DOMAIN set, exiting"
    exit 2
fi

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$OSCAR_TEMPLATE_TYPE" ] && OSCAR_TEMPLATE_TYPE="core"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

JOB_NAME="oscar-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-oscar"

OSCAR_ENABLE_WAVEFRONT_PROXY="true"

if [[ "$OSCAR_TEMPLATE_TYPE" == "core" ]]; then
    OSCAR_ENABLE_COTURN="true"
    OSCAR_ENABLE_SHARD="true"
    OSCAR_ENABLE_SITE_INGRESS="true"
    OSCAR_ENABLE_HAPROXY_REGION="true"
    OSCAR_ENABLE_AUTOSCALER="true"
    OSCAR_ENABLE_LOKI="true"
elif [[ "$OSCAR_TEMPLATE_TYPE" == "ops" ]]; then
    OSCAR_ENABLE_COTURN="false"
    OSCAR_ENABLE_SHARD="false"
    OSCAR_ENABLE_SITE_INGRESS="false"
    OSCAR_ENABLE_HAPROXY_REGION="false"
    OSCAR_ENABLE_AUTOSCALER="false"
    OSCAR_ENABLE_LOKI="true"
else
    echo "Unsupported OSCAR_TEMPLATE_TYPE, exiting"
    exit 3
fi

OSCAR_ENABLE_SKYNET="false"
if [[ -n $OSCAR_CUSTOM_SKYNET_HOSTS ]]; then
    OSCAR_ENABLE_SKYNET="true"
    SKYNET_ALT_HOSTNAME=$OSCAR_CUSTOM_SKYNET_HOSTS
elif [[ -n $SKYNET_ALT_HOSTNAME ]]; then
    OSCAR_ENABLE_SKYNET="true"
fi

OSCAR_ENABLE_WHISPER="false"
if [[ -n $OSCAR_CUSTOM_WHISPER_HOSTS ]]; then
    OSCAR_ENABLE_WHISPER="true"
    WHISPER_HOSTNAME=$OSCAR_CUSTOM_WHISPER_HOSTS
else
    WHISPER_URL="$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".jigasi_transcriber_whisper_websocket_url" -)"
    if [[ "$WHISPER_URL" != "null" ]]; then
        OSCAR_ENABLE_WHISPER="true"
        basename $WHISPER_URL
        basename $(dirname $WHISPER_URL)
        WHISPER_HOSTNAME=$(echo $WHISPER_URL | cut -d'/' -f3 | cut -d':' -f1)
    fi
fi

OSCAR_ENABLE_CUSTOM_HTTPS="false"
OSCAR_CUSTOM_HTTPS_TARGETS=$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".oscar_custom_https_url_targets" | tr -d '\n')
if [[ "$OSCAR_CUSTOM_HTTPS_TARGETS" != "null" ]]; then
    OSCAR_ENABLE_CUSTOM_HTTPS="true"
fi

[ -z "$CLOUDPROBER_VERSION" ] && CLOUDPROBER_VERSION="latest"

cat > "./oscar.hcl" <<EOF
datacenters=["$NOMAD_DC"]
oscar_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
cloudprober_version="$CLOUDPROBER_VERSION"
oracle_region="$ORACLE_REGION"
top_level_domain="$TOP_LEVEL_DNS_ZONE_NAME"
domain="$DOMAIN"
environment="$ENVIRONMENT"
enable_site_ingress=$OSCAR_ENABLE_SITE_INGRESS
enable_haproxy_region=$OSCAR_ENABLE_HAPROXY_REGION
enable_coturn=$OSCAR_ENABLE_COTURN
enable_shard=$OSCAR_ENABLE_SHARD
enable_autoscaler=$OSCAR_ENABLE_AUTOSCALER
enable_wavefront_proxy=$OSCAR_ENABLE_WAVEFRONT_PROXY
enable_skynet=$OSCAR_ENABLE_SKYNET
skynet_hostname="$SKYNET_ALT_HOSTNAME"
enable_whisper=$OSCAR_ENABLE_WHISPER
whisper_hostname="$WHISPER_HOSTNAME"
enable_loki=$OSCAR_ENABLE_LOKI
enable_custom_https=$OSCAR_ENABLE_CUSTOM_HTTPS
custom_https_targets="$OSCAR_CUSTOM_HTTPS_TARGETS"
EOF

nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./oscar.hcl" \
  $PACKS_DIR/jitsi_oscar

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning nomad oscar job, exiting"
    rm ./oscar.hcl
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
  -var-file "./oscar.hcl" \
  $PACKS_DIR/jitsi_oscar

if [ $? -ne 0 ]; then
    echo "Failed to run nomad oscar job, exiting"
    rm ./oscar.hcl
    exit 5
fi

rm ./oscar.hcl

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh