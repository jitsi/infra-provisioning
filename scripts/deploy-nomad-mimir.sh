#!/bin/bash
# Deploys the per-region Mimir cluster (nomad/mimir-cluster.hcl) and its CNAME.
# Pattern from deploy-nomad-loki.sh. Object-storage credentials come from the
# dedicated Vault kv secret/default/mimir/s3 (read by the job template, tempo
# pattern), NOT from nomad_s3fs_credentials.
#
# Prerequisites (Phase 0 of doc/mimir-cluster-plan.md):
#   - terraform/volumes-mimir applied and the consul nodes rotated so
#     /mnt/bv/mimir-N is mounted and registered as nomad host volume mimir-N
#   - bucket mimir-$ENVIRONMENT exists in the region (scripts/create-buckets-oracle.sh)
#   - Vault kv secret/default/mimir/s3 with access_key / secret_key scoped to that bucket
#   - consul NSG allows 7947/tcp+udp (terraform/consul-server)

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

[ -z "$LOCAL_REGION" ] && LOCAL_REGION="$OCI_LOCAL_REGION"
[ -z "$LOCAL_REGION" ] && LOCAL_REGION="us-phoenix-1"

if [ -z "$NOMAD_ADDR" ]; then
    export NOMAD_ADDR="https://$ENVIRONMENT-$LOCAL_REGION-nomad.$TOP_LEVEL_DNS_ZONE_NAME"
fi

[ -z "$MIMIR_HOSTNAME" ] && MIMIR_HOSTNAME="$ENVIRONMENT-$ORACLE_REGION-mimir.$TOP_LEVEL_DNS_ZONE_NAME"

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"
export NOMAD_VAR_mimir_hostname="${MIMIR_HOSTNAME}"
export NOMAD_VAR_oracle_s3_namespace="$ORACLE_S3_NAMESPACE"
JOB_NAME="mimir-$ORACLE_REGION"

[ -z "$ENVIRONMENT_TYPE" ] && ENVIRONMENT_TYPE="dev"
if [[ "$ENVIRONMENT_TYPE" = "prod" ]]; then
    export NOMAD_VAR_environment_type="prod"
else
    export NOMAD_VAR_environment_type="nonprod"
fi

# optional per-environment overrides (sites/$ENVIRONMENT/stack-env.sh)
[ -n "$MIMIR_VERSION" ] && export NOMAD_VAR_mimir_version="$MIMIR_VERSION"
[ -n "$MIMIR_RETENTION_PERIOD" ] && export NOMAD_VAR_retention_period="$MIMIR_RETENTION_PERIOD"
[ -n "$MIMIR_MAX_GLOBAL_SERIES" ] && export NOMAD_VAR_max_global_series_per_user="$MIMIR_MAX_GLOBAL_SERIES"
[ -n "$MIMIR_INGESTION_RATE" ] && export NOMAD_VAR_ingestion_rate="$MIMIR_INGESTION_RATE"
[ -n "$MIMIR_INGESTION_BURST_SIZE" ] && export NOMAD_VAR_ingestion_burst_size="$MIMIR_INGESTION_BURST_SIZE"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/mimir-cluster.hcl" | nomad job run -var="dc=$NOMAD_DC" -

if [ $? -ne 0 ]; then
    echo "Failed to run nomad mimir job, exiting"
    exit 5
fi

export RESOURCE_NAME_ROOT="${ENVIRONMENT}-${ORACLE_REGION}-mimir"

export CNAME_VALUE="$RESOURCE_NAME_ROOT"
export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
$LOCAL_PATH/create-oracle-cname-stack.sh
