#!/bin/bash

# last tag 0.0.2
docker buildx build --no-cache --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag aaronkvanmeerten/ops-repo:$TAG --tag aaronkvanmeerten/ops-repo:latest .
