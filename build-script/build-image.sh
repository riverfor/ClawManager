#!/bin/bash
set -euo pipefail

docker build \
    --no-cache \
    --build-arg GOPROXY=https://goproxy.cn,direct \
    --build-arg GOSUMDB=off \
    --build-arg GOFLAGS=-x \
    -t ghcr.io/quseit/clawmanager:latest \
    "$(pwd)"
