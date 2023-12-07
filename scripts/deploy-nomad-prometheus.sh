#!/bin/bash

set -x

if [ -z "$ENVIRONMENT" ]; then
    echo "No ENVIRONMENT set, exiting"
    exit 2
fi

if [ -z "$ORACLE_REGION" ]; then
    echo "No ORACLE_REGION set, exiting"
    exit 2
fi

LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

[ -e "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../sites/$ENVIRONMENT/stack-env.sh"

[ -e "$LOCAL_PATH/../clouds/all.sh" ] && . "$LOCAL_PATH/../clouds/all.sh"
[ -e "$LOCAL_PATH/../clouds/oracle.sh" ] && . "$LOCAL_PATH/../clouds/oracle.sh"

[ -z "$VAULT_PASSWORD_FILE" ] && VAULT_PASSWORD_FILE="$LOCAL_PATH/../.vault-password.txt"

[ -z "$ENVIRONMENT_CONFIGURATION_FILE" ] && ENVIRONMENT_CONFIGURATION_FILE="$LOCAL_PATH/../sites/$ENVIRONMENT/vars.yml"

NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$PROMETHEUS_VERSION" ] && PROMETHEUS_VERSION="2.47.2" # can't use latest because the tpl adds a 'v' as a prefix

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-prometheus"

set +x

cat > "./prometheus.hcl" <<EOF
datacenters=["$NOMAD_DC"]
prometheus_task={
    driver="docker",
    version="$PROMETHEUS_VERSION",
    cli_args=[
        "--config.file=/etc/prometheus/config/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--web.listen-address=0.0.0.0:9090",
        "--web.console.libraries=/usr/share/prometheus/console_libraries",
        "--web.console.templates=/usr/share/prometheus/consoles",
    ]
}
prometheus_group_network={
    mode  = "host",
    ports = {
      "http" = 9090,
    },
}
EOF

set -x
set +e

JOB_NAME="prometheus-$ORACLE_REGION"

nomad-pack registry add community github.com/hashicorp/nomad-pack-community-registry

cat prometheus.hcl

nomad-pack plan --registry=community --parser-v1 \
  --name "$JOB_NAME" \
  -var "job_name=$JOB_NAME" \
  -var-file "./prometheus.hcl" \
  prometheus

PLAN_RET=$?

if [ $PLAN_RET -gt 1 ]; then
    echo "Failed planning nomad prometheus job, exiting"
    rm ./prometheus.hcl
    exit 4
else
    if [ $PLAN_RET -eq 1 ]; then
        echo "Plan was successful, will make changes"
    fi
    if [ $PLAN_RET -eq 0 ]; then
        echo "Plan was successful, no changes needed"
    fi
fi

nomad-pack run --registry=community --parser-v1 \
  -var "job_name=$JOB_NAME" \
  -var-file "./prometheus.hcl" \
  prometheus

if [ $? -ne 0 ]; then
    echo "Failed to run nomad prometheus job, exiting"
    rm ./prometheus.hcl
    exit 5
fi

rm ./prometheus.hcl
