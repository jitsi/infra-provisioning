#!/bin/bash
[ -z "$TAG" ] && TAG=$1
# if not set tag is git short hash
[ -z "$TAG" ] && TAG="$(git rev-parse --short HEAD)"

[ -z "$PRIVATE_DOCKER_REGISTRY" ] && PRIVATE_DOCKER_REGISTRY="ops-prod-us-phoenix-1-registry.jitsi.net/selenium/node-mixed"

docker buildx build --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag $PRIVATE_DOCKER_REGISTRY:$TAG --tag $PRIVATE_DOCKER_REGISTRY:latest .
