#!/bin/bash
# Single source of truth for the default image architecture per IMAGE_TYPE.
#
# Most image types build aarch64 by default; only the types listed below default
# to x86_64. This is sourced by the build-*-oracle.sh scripts, by
# check-build-oracle-image.sh, and (via Utils.groovy DefaultImageArch) by the
# build-image-oracle Jenkins pipeline when constructing its concurrency lock, so
# that the lock name always matches the architecture actually built.
#
# Sets and exports IMAGE_ARCH. Callers typically guard with:
#   [ -z "$IMAGE_ARCH" ] && default_arch_from_type "<IMAGE_TYPE>"
function default_arch_from_type() {
    DTYPE="$1"
    IMAGE_ARCH="aarch64"
    case "$DTYPE" in
        FocalBase|GPU|JavaJibri|SeleniumGrid)
            IMAGE_ARCH="x86_64"
            ;;
    esac
    export IMAGE_ARCH
}
