#!/bin/bash
# Update Oracle Cloud image tags with actual installed versions
# Called by Packer shell-local post-processor after image creation

set -e

VERSIONS_FILE="$1"
MANIFEST_FILE="$2"
REGION="$3"
TAG_NAMESPACE="$4"

if [ -z "$VERSIONS_FILE" ] || [ -z "$MANIFEST_FILE" ] || [ -z "$REGION" ] || [ -z "$TAG_NAMESPACE" ]; then
    echo "Usage: $0 <versions_file> <manifest_file> <region> <tag_namespace>"
    exit 1
fi

if [ ! -f "$VERSIONS_FILE" ]; then
    echo "Error: Versions file not found: $VERSIONS_FILE"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Error: Manifest file not found: $MANIFEST_FILE"
    exit 1
fi

# Extract image OCID from manifest (last build's artifact_id)
IMAGE_OCID=$(jq -r '.builds[-1].artifact_id' "$MANIFEST_FILE")

if [ -z "$IMAGE_OCID" ] || [ "$IMAGE_OCID" == "null" ]; then
    echo "Error: Could not extract image OCID from manifest"
    exit 1
fi

# Extract actual versions from installed-versions.json
JICOFO_VERSION=$(jq -r '.jicofo_version' "$VERSIONS_FILE")
JITSI_MEET_VERSION=$(jq -r '.jitsi_meet_version' "$VERSIONS_FILE")
PROSODY_VERSION=$(jq -r '.prosody_version' "$VERSIONS_FILE")

SIGNAL_VERSION="${JICOFO_VERSION}-${JITSI_MEET_VERSION}-${PROSODY_VERSION}"

echo "Updating image tags for $IMAGE_OCID"
echo "  Actual versions: Jicofo=$JICOFO_VERSION, JitsiMeet=$JITSI_MEET_VERSION, Prosody=$PROSODY_VERSION"
echo "  Signal version: $SIGNAL_VERSION"

# Call Python script to update tags
SCRIPT_DIR="$(dirname "$0")"
"$SCRIPT_DIR/oracle_custom_images.py" \
    --update_version_tags \
    --image_id "$IMAGE_OCID" \
    --region "$REGION" \
    --tag_namespace "$TAG_NAMESPACE" \
    --jicofo_version "$JICOFO_VERSION" \
    --jitsi_meet_version "$JITSI_MEET_VERSION" \
    --prosody_version "$PROSODY_VERSION"

# Cleanup versions file (manifest preserved for replication stage)
rm -f "$VERSIONS_FILE"

echo "Image tags updated successfully"
echo "Manifest file preserved at: $MANIFEST_FILE"
