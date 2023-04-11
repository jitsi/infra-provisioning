#!/bin/bash

# last tag 0.0.21
docker buildx build --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag aaronkvanmeerten/ops-agent-inbound:$TAG --tag aaronkvanmeerten/ops-agent-inbound:latest .
