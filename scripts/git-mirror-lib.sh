#!/usr/bin/env bash
# Shared gate for the in-region git mirror (JIT-16092).
#
# An environment turns the mirror on once, with GIT_MIRROR_HOST=auto in
# sites/<env>/stack-env.sh, and every stack that plumbs GIT_MIRROR_HOST into
# user-data calls this before it does.
#
# The gate exists because mirrors live only in NOMAD_REGIONS while several
# environments run clouds in regions with no nomad at all -- beta has clouds in
# five regions and mirrors in three. "auto" in one of the other two derives a
# hostname that does not resolve. Boots would still succeed, since the boot path
# falls back to github, but that turns the fallback from an outage measure into
# part of normal operation and makes a real mirror failure indistinguishable
# from a region that never had one.
#
# Expects ENVIRONMENT, ORACLE_REGION and NOMAD_REGIONS, i.e. call it after
# sites/<env>/stack-env.sh and the clouds files have been sourced.
function resolve_git_mirror_host() {
  # unset means the stack is not opted in, which is the default everywhere
  if [ -z "$GIT_MIRROR_HOST" ]; then
    echo "No GIT_MIRROR_HOST set for $ENVIRONMENT, booting from github"
    return 0
  fi
  # an explicit hostname is somebody naming a mirror on purpose; leave it alone
  if [ "$GIT_MIRROR_HOST" != "auto" ]; then
    echo "Using the explicitly configured git mirror $GIT_MIRROR_HOST for $ENVIRONMENT"
    return 0
  fi
  if [[ " $NOMAD_REGIONS " != *" $ORACLE_REGION "* ]]; then
    echo "No git mirror in $ORACLE_REGION (not in NOMAD_REGIONS '$NOMAD_REGIONS'), booting from github"
    export GIT_MIRROR_HOST=""
  else
    echo "Using the in-region git mirror for $ENVIRONMENT in $ORACLE_REGION"
  fi
}

# Emits a --metadata_extras value carrying the mirror host, optionally appended
# to extras the caller already has.
#
# scripts/rotate_instance_configuration_oracle.py rebuilds user-data from
# terraform/lib plus this string plus the runner, so it never sees the terraform
# variable. Without this, the first rotation after a create silently drops the
# mirror and the instance goes back to cloning from github.
#
# Always safe to pass through: the tool ignores an empty --metadata_extras.
function git_mirror_metadata_extras() {
  local extras="$1"
  if [ -n "$GIT_MIRROR_HOST" ]; then
    extras="${extras:+$extras; }export GIT_MIRROR_HOST=$GIT_MIRROR_HOST"
  fi
  echo "$extras"
}
