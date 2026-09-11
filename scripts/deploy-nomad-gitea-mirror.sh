#!/bin/bash

# Deploys the per-region Gitea mirror (nomad/gitea-mirror.hcl). Modeled on
# deploy-nomad-ops-repo.sh: dc = $ENVIRONMENT-$ORACLE_REGION, served internal-only
# via a Fabio int-urlprefix tag on the mirror hostname. See JIT-16092.
#
# Vault prerequisites (in the vault this environment's nomad uses), all read by
# the job and granted via gitea_mirror_secret_paths in infra-customizations-private:
#   secret/default/gitea/admin      username, password, email of the site admin
#   secret/default/gitea/github     token: a GitHub PAT that can read the private repo
#   secret/default/gitea/read-user  username, password of the read-only boot user
#                                   (scripts/seed-gitea-read-user.sh)

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

# Repos to mirror. The three infra repos everywhere: those are what a VM boot
# clones (infra-configuration and infra-customizations) and what the Jenkins
# checkouts use.
#
# jitsi-meet is extra, and only for the build tooling, which runs in the ops
# environments. It is by far the largest repo mirrored (~890MB against ~150MB
# for the rest combined), it dominates a cold replica's first sync, and the
# health gate makes the whole replica wait on it, which is why this job carries
# a 20m healthy_deadline. No VM boot has ever needed it.
#
# The test used to be on the region alone, so *every* environment's us-phoenix-1
# mirror pulled jitsi-meet -- prod-8x8, stage-8x8, beta and torture-test
# included, none of which have any use for it. Keyed on the environment as well
# now. Override either list, or GITEA_REQUIRED_REPOS wholesale (HCL/JSON list
# syntax, e.g. '["infra-configuration","jitsi-meet"]').
[ -z "$GITEA_JITSI_MEET_ENVIRONMENTS" ] && GITEA_JITSI_MEET_ENVIRONMENTS="ops-dev ops-prod"
[ -z "$GITEA_JITSI_MEET_REGION" ] && GITEA_JITSI_MEET_REGION="us-phoenix-1"

if [ -z "$GITEA_REQUIRED_REPOS" ]; then
    if [[ " $GITEA_JITSI_MEET_ENVIRONMENTS " == *" $ENVIRONMENT "* ]] && [ "$ORACLE_REGION" == "$GITEA_JITSI_MEET_REGION" ]; then
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
# fixed name would be clobbered by the next region's deploy.
#
# Overridable through GITEA_JOB_NAME, so a test instance can run alongside the
# real one. Deliberately NOT JOB_NAME: Jenkins exports JOB_NAME as the name of
# the running job, so reading that here would deploy a nomad job called
# "provision-nomad-gitea-mirror" and leave the real mirror untouched.
[ -z "$GITEA_JOB_NAME" ] && GITEA_JOB_NAME="gitea-mirror-$ORACLE_REGION"

sed -e "s/\[JOB_NAME\]/$GITEA_JOB_NAME/" "$NOMAD_JOB_PATH/gitea-mirror.hcl" | nomad job run -var="dc=$NOMAD_DC" -
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
