#!/bin/bash

# last tag 0.0.1
CACHE_FLAG="--no-cache"
docker buildx build $CACHE_FLAG --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag aaronkvanmeerten/ops-git:$TAG --tag aaronkvanmeerten/ops-git:latest .