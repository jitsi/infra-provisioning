#!/bin/bash
if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

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

if [ ! -z "$TEMPLATE_TYPE_OVERRIDE" ]; then
    CLOUDPROBER_TEMPLATE_TYPE="$TEMPLATE_TYPE_OVERRIDE"
fi

[ -z "$CLOUDPROBER_TEMPLATE_TYPE" ] && CLOUDPROBER_TEMPLATE_TYPE="base"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="dev"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

JOB_NAME="cloudprober-$ORACLE_REGION"
PACKS_DIR="$LOCAL_PATH/../nomad/jitsi_packs/packs"

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-cloudprober"

# init generic probes used by every environment 
CLOUDPROBER_ENABLE_ALERTMANAGER="true"
CLOUDPROBER_ENABLE_LOKI="true"
CLOUDPROBER_ENABLE_PROMETHEUS="true"
CLOUDPROBER_ENABLE_WAVEFRONT_PROXY="true"
CLOUDPROBER_ENABLE_LATENCY="true"

# init generic probes used by specific environments
CLOUDPROBER_ENABLE_AUTOSCALER="false"
CLOUDPROBER_ENABLE_COTURN="false"
CLOUDPROBER_ENABLE_CUSTOM_HTTPS="false"
CLOUDPROBER_ENABLE_HAPROXY_REGION="false"
CLOUDPROBER_ENABLE_SHARD="false"
CLOUDPROBER_ENABLE_SKYNET="false"
CLOUDPROBER_ENABLE_SITE_INGRESS="false"
CLOUDPROBER_ENABLE_VAULT="false"
CLOUDPROBER_ENABLE_WHISPER="false"
CLOUDPROBER_ENABLE_CANARY="false"

# add probes based on template type
if [[ "$CLOUDPROBER_TEMPLATE_TYPE" == "core" ]]; then
    CLOUDPROBER_ENABLE_AUTOSCALER="true"
    CLOUDPROBER_ENABLE_COTURN="true"
    CLOUDPROBER_ENABLE_HAPROXY_REGION="true"
    CLOUDPROBER_ENABLE_SHARD="true"
    CLOUDPROBER_ENABLE_SITE_INGRESS="true"
elif [[ "$CLOUDPROBER_TEMPLATE_TYPE" == "ops" ]]; then
    CLOUDPROBER_ENABLE_VAULT="true"
elif [[ "$CLOUDPROBER_TEMPLATE_TYPE" != "base" ]]; then
    echo "Unsupported CLOUDPROBER_TEMPLATE_TYPE (should be base, core, or ops), exiting"
    exit 3
fi

# add custom https probes for environments that have them (typically just ops)
CLOUDPROBER_CUSTOM_HTTPS_TARGETS=$(cat $ENVIRONMENT_CONFIGURATION_FILE | yq eval ".cloudprober_custom_https_url_targets" | tr -d '\n')
if [[ "$CLOUDPROBER_CUSTOM_HTTPS_TARGETS" != "null" ]]; then
    CLOUDPROBER_ENABLE_CUSTOM_HTTPS="true"
fi

[ -z "$CLOUDPROBER_VERSION" ] && CLOUDPROBER_VERSION="v0.13.8"

cat > "./cloudprober.hcl" <<EOF
datacenters=["$NOMAD_DC"]
cloudprober_hostname="${RESOURCE_NAME_ROOT}.${TOP_LEVEL_DNS_ZONE_NAME}"
cloudprober_version="$CLOUDPROBER_VERSION"
oracle_region="$ORACLE_REGION"
top_level_domain="$TOP_LEVEL_DNS_ZONE_NAME"
domain="$DOMAIN"
environment="$ENVIRONMENT"
enable_site_ingress=$CLOUDPROBER_ENABLE_SITE_INGRESS
enable_haproxy_region=$CLOUDPROBER_ENABLE_HAPROXY_REGION
enable_coturn=$CLOUDPROBER_ENABLE_COTURN
enable_shard=$CLOUDPROBER_ENABLE_SHARD
enable_autoscaler=$CLOUDPROBER_ENABLE_AUTOSCALER
enable_wavefront_proxy=$CLOUDPROBER_ENABLE_WAVEFRONT_PROXY
enable_loki=$CLOUDPROBER_ENABLE_LOKI
enable_custom_https=$CLOUDPROBER_ENABLE_CUSTOM_HTTPS
custom_https_targets="$CLOUDPROBER_CUSTOM_HTTPS_TARGETS"
enable_prometheus=$CLOUDPROBER_ENABLE_PROMETHEUS
enable_alertmanager=$CLOUDPROBER_ENABLE_ALERTMANAGER
enable_vault=$CLOUDPROBER_ENABLE_VAULT
enable_canary=$CLOUDPROBER_ENABLE_LATENCY
EOF

nomad-pack plan --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./cloudprober.hcl" \
  $PACKS_DIR/jitsi_cloudprober

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning nomad cloudprober job, exiting"
    rm ./cloudprober.hcl
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
  -var-file "./cloudprober.hcl" \
  $PACKS_DIR/jitsi_cloudprober

if [ $? -ne 0 ]; then
    echo "Failed to run nomad cloudprober job, exiting"
    rm ./cloudprober.hcl
    exit 5
fi

rm ./cloudprober.hcl

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh