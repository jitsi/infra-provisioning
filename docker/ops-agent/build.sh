#!/bin/bash

# last tag 0.0.20
docker buildx build --platform=linux/arm64,linux/amd64 --push --pull --progress=plain --tag aaronkvanmeerten/ops-agent:$TAG --tag aaronkvanmeerten/ops-agent:latest .
