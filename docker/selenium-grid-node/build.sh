#!/bin/bash
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")

# One value drives both the node image base and the hub image tag.
. "$LOCAL_PATH/../../scripts/selenium-version.sh"

[ -z "$TAG" ] && TAG=$1
# if not set tag is git short hash
[ -z "$TAG" ] && TAG="$(git rev-parse --short HEAD)"

[ -z "$PRIVATE_DOCKER_REGISTRY" ] && PRIVATE_DOCKER_REGISTRY="ops-prod-us-phoenix-1-registry.jitsi.net/selenium/node-mixed"

echo "Building selenium grid node image: selenium $SELENIUM_VERSION, tag $TAG"

# arm64 only: Google now ships Chrome for linux-arm64 and Chrome for Testing
# publishes linux-arm64 chromedrivers from Chrome 153 onwards, so amd64 nodes
# are no longer needed. Scale the x86 instance pool to 0 before rolling this out.
docker buildx build --platform=linux/arm64 --push --pull --progress=plain \
  --build-arg CACHEBUST=$(date +%s) \
  --build-arg SELENIUM_VERSION="$SELENIUM_VERSION" \
  --tag $PRIVATE_DOCKER_REGISTRY:$TAG --tag $PRIVATE_DOCKER_REGISTRY:latest .
