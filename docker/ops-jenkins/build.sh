#!/bin/bash

# last tag 0.0.10
# CACHE_FLAG="--no-cache"
docker buildx build $CACHE_FLAG --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag aaronkvanmeerten/ops-jenkins:$TAG --tag aaronkvanmeerten/ops-jenkins:latest .
