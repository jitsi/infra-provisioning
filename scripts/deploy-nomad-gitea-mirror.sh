#!/bin/bash

# Deploys the per-region Gitea mirror (nomad/gitea-mirror.hcl). Modeled on
# deploy-nomad-ops-repo.sh: dc = $ENVIRONMENT-$ORACLE_REGION, served internal-only
# via a Fabio int-urlprefix tag on the mirror hostname. See JIT-16092.

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

NOMAD_JOB_PATH="$LOCAL_PATH/../nomad"
NOMAD_DC="$ENVIRONMENT-$ORACLE_REGION"

# Regional mirror hostname. Internal-only (served behind Fabio's int- prefix),
# one per env+region so boots clone from their own region's mirror. Overridable
# for test instances so they don't collide with the production route.
[ -z "$GITEA_HOSTNAME" ] && GITEA_HOSTNAME="${ENVIRONMENT}-${ORACLE_REGION}-git.${TOP_LEVEL_DNS_ZONE_NAME}"
export NOMAD_VAR_gitea_hostname="$GITEA_HOSTNAME"

# Repos to mirror. jitsi-meet is only cloned by boots in us-phoenix-1 (where the
# Jenkins/build host lives), so it is mirrored there only; everywhere else just
# the three infra repos. Override wholesale with GITEA_REQUIRED_REPOS (HCL/JSON
# list syntax, e.g. '["infra-configuration","jitsi-meet"]').
if [ -z "$GITEA_REQUIRED_REPOS" ]; then
    if [ "$ORACLE_REGION" == "us-phoenix-1" ]; then
        GITEA_REQUIRED_REPOS='["infra-configuration","infra-provisioning","infra-customizations-private","jitsi-meet"]'
    else
        GITEA_REQUIRED_REPOS='["infra-configuration","infra-provisioning","infra-customizations-private"]'
    fi
fi
export NOMAD_VAR_required_repos="$GITEA_REQUIRED_REPOS"

# Optional overrides (all have sane defaults in the job).
[ -n "$GITEA_IMAGE_VERSION" ] && export NOMAD_VAR_image_version="$GITEA_IMAGE_VERSION"
[ -n "$GITEA_MIRROR_INTERVAL" ] && export NOMAD_VAR_mirror_interval="$GITEA_MIRROR_INTERVAL"

export NOMAD_VAR_dc="$NOMAD_DC"

# Per-region job name, same pattern as loki-/prometheus-/tempo-$ORACLE_REGION:
# the Nomad region is shared across all of an environment's datacenters, so a
# fixed name would be clobbered by the next region's deploy. Overridable so a
# test instance can run alongside the real one.
[ -z "$JOB_NAME" ] && JOB_NAME="gitea-mirror-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$JOB_NAME/" "$NOMAD_JOB_PATH/gitea-mirror.hcl" | nomad job run -var="dc=$NOMAD_DC" -
RET=$?

# Route53 CNAME for the mirror hostname -> the region's internal general-pool
# (Fabio) target, same pattern as deploy-nomad-loki.sh / -prometheus.sh. The
# record label is derived from GITEA_HOSTNAME so an overridden test hostname
# gets its own record; skipped if the hostname is outside the top-level zone.
if [[ "$GITEA_HOSTNAME" == *".${TOP_LEVEL_DNS_ZONE_NAME}" ]]; then
    export RESOURCE_NAME_ROOT="${GITEA_HOSTNAME%.${TOP_LEVEL_DNS_ZONE_NAME}}"
    export STACK_NAME="${RESOURCE_NAME_ROOT}-cname"
    export UNIQUE_ID="${RESOURCE_NAME_ROOT}"
    export CNAME_TARGET="${ENVIRONMENT}-${ORACLE_REGION}-nomad-pool-general-internal.${DEFAULT_DNS_ZONE_NAME}"
    export CNAME_VALUE="${RESOURCE_NAME_ROOT}"
    $LOCAL_PATH/create-oracle-cname-stack.sh
else
    echo "GITEA_HOSTNAME $GITEA_HOSTNAME is not under $TOP_LEVEL_DNS_ZONE_NAME, skipping CNAME creation"
fi

exit $RET
