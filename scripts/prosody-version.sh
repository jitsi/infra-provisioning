#!/bin/bash
# Resolve a PROSODY_VERSION of 'latest' to the version the prosody apt repo actually
# serves right now, so callers can reason about a real version instead of the literal
# string 'latest'.
#
# This exists for the image-existence checks. Asking for prosody 'latest' used to
# produce a signal version no image could ever carry ("1205-9442-latest"), so the check
# never matched and every release rebuilt the signal image. Resolving first means the
# check compares like with like: the image is reused when it already has today's
# prosody, and rebuilt as soon as upstream publishes a new one.
#
# It deliberately does NOT pin the install. build-signal-oracle.sh still installs
# prosody from apt without a version pin, and build-signal.yml tags the finished image
# with whatever dpkg reports afterwards, so the tag always reflects reality even if
# upstream publishes between this lookup and the build.
#
# Sourced by check-build-oracle-image-for-clouds.sh and build-signal-oracle.sh.

[ -z "$PROSODY_APT_REPO_URL" ] && PROSODY_APT_REPO_URL="http://packages.prosody.im/debian"
[ -z "$PROSODY_APT_PACKAGE" ] && PROSODY_APT_PACKAGE="prosody"

# ubuntu release of the base image the signal image is built on top of, which is the
# apt suite prosody packages are published under
function prosody_apt_suite() {
    case "$1" in
        FocalBase) echo "focal" ;;
        JammyBase) echo "jammy" ;;
        # NobleBase, and the default in build-signal-oracle.sh when none is configured
        *) echo "noble" ;;
    esac
}

# the version wildcard ansible installs with (roles/prosody prosody_apt_version, e.g.
# "13.*"), so a lookup here can never select a version the build would not install
function prosody_apt_version_pattern() {
    local local_path site_vars config_vars role_defaults pattern
    local_path=$(dirname "${BASH_SOURCE[0]}")
    site_vars="$local_path/../sites/$ENVIRONMENT/vars.yml"
    config_vars="$local_path/../config/vars.yml"
    role_defaults="$local_path/../../infra-configuration/ansible/roles/prosody/defaults/main.yml"

    for f in "$site_vars" "$config_vars" "$role_defaults"; do
        [ -e "$f" ] || continue
        pattern="$(yq eval '.prosody_apt_version' "$f" 2>/dev/null)"
        if [ -n "$pattern" ] && [ "$pattern" != "null" ]; then
            echo "$pattern"
            return 0
        fi
    done

    # no pattern found: accept whatever the repo offers
    echo '*'
}

# Sets PROSODY_VERSION to a concrete version when it is 'latest'. Leaves it alone on
# any lookup failure, which just restores the old behaviour of always building.
function resolve_latest_prosody_version() {
    [ "$PROSODY_VERSION" == "latest" ] || return 0

    local base_image_type suite arch pattern packages resolved
    base_image_type="$BASE_IMAGE_TYPE"
    [ -z "$base_image_type" ] && base_image_type="$SIGNAL_BASE_IMAGE_TYPE"
    suite=$(prosody_apt_suite "$base_image_type")

    arch="amd64"
    [ "$IMAGE_ARCH" == "aarch64" ] && arch="arm64"

    pattern=$(prosody_apt_version_pattern)

    packages=$(curl -fsSL --max-time 30 "$PROSODY_APT_REPO_URL/dists/$suite/main/binary-$arch/Packages.gz" 2>/dev/null | gunzip -c 2>/dev/null)
    if [ -z "$packages" ]; then
        echo "## prosody-version: could not read $PROSODY_APT_REPO_URL for $suite/$arch, leaving PROSODY_VERSION as 'latest'"
        return 0
    fi

    # every version of the package the repo offers, kept only if it matches the wildcard
    # apt would install with, reduced to the upstream version dpkg will report, highest last
    resolved=$(echo "$packages" | awk -v pkg="$PROSODY_APT_PACKAGE" '
        /^Package: /{ current=$2 }
        /^Version: /{ if (current == pkg) print $2 }' | \
        while read -r full_version; do
            # $pattern is an apt-style glob ("13.*"), so match it the way case does
            case "$full_version" in
                $pattern) echo "${full_version%%-*}" ;;
            esac
        done | sort -V | tail -1)

    if [ -z "$resolved" ]; then
        echo "## prosody-version: no $PROSODY_APT_PACKAGE version matching '$pattern' in $suite/$arch, leaving PROSODY_VERSION as 'latest'"
        return 0
    fi

    echo "## prosody-version: latest prosody matching '$pattern' in $suite/$arch is $resolved"
    PROSODY_VERSION="$resolved"
    export PROSODY_VERSION
}
