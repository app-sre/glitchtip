#!/bin/bash
set -exv

BASE_IMG="glitchtip"
QUAY_IMAGE="quay.io/app-sre/${BASE_IMG}"
IMG="${BASE_IMG}:latest"
GIT_HASH=${GIT_COMMIT:0:7}

# Build Image
docker build . -t ${IMG}

# tag and push the image
docker login  -u="$QUAY_USER" -p="$QUAY_TOKEN" quay.io
docker tag ${IMG} "${QUAY_IMAGE}:latest"
docker push "${QUAY_IMAGE}:latest"
docker tag ${IMG} "${QUAY_IMAGE}:${GIT_HASH}"
docker push "${QUAY_IMAGE}:${GIT_HASH}"
