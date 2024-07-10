#!/bin/bash
set -ev

test -z "$NO_PUSH" && docker login -u="$QUAY_USER" -p="$QUAY_TOKEN" quay.io

# Force image pull
docker image rm --force quay.io/app-sre/qontract-reconcile:latest

for i in "glitchtip Dockerfile" "glitchtip-acceptance Dockerfile.acceptance"
do
    set -- $i # convert the "tuple" into the param args $1 $2...
    IMG_NAME="$1"
    DOCKERFILE="$2"

    QUAY_IMAGE="quay.io/app-sre/$IMG_NAME"
    IMG="$IMG_NAME:latest"
    if [ -n "$GIT_COMMIT" ]; then
        GIT_HASH=${GIT_COMMIT:0:7}
    fi

    # Build Image
    echo "Building $IMG_NAME with $DOCKERFILE ..."
    docker build . -f "$DOCKERFILE" -t "$IMG"

    # Tag and push the image
    docker tag "$IMG" "$QUAY_IMAGE:latest"
    test -z "$NO_PUSH" && docker push "$QUAY_IMAGE:latest"
    if [ -n "$GIT_HASH" ]; then
        docker tag "$IMG" "$QUAY_IMAGE:$GIT_HASH"
        test -z "$NO_PUSH" && docker push "$QUAY_IMAGE:$GIT_HASH"
    fi
done
exit 0
