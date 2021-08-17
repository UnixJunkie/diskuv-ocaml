#!/bin/bash
# ----------------------------
# moby-download-docker-image.sh MOBYDIR DOCKER_IMAGE DOCKER_TARGET_ARCH
#
# Meant to be called from Cygwin so there is a working `jq` for the Moby download-frozen-image-v2.sh.
# If we use MSYS2 jq then we run into `jq` shell quoting failures.

set -euf -o pipefail

MOBYDIR=$1
shift

DOCKER_IMAGE=$1
shift

DOCKER_TARGET_ARCH=$1
shift

FROZEN_SCRIPT=$MOBYDIR/download-frozen-image-v2.sh

# DOCKER_IMAGE=ocaml/opam:windows-msvc-20H2, DOCKER_TARGET_ARCH=arm64 -> SIMPLE_NAME=ocaml-opam-windows-msvc-20H2-arm64
# !!!Keep in sync with moby-extract-opam-root.sh (refactor into common place if we share more than twice)!!!
SIMPLE_NAME=$DOCKER_IMAGE
SIMPLE_NAME=${SIMPLE_NAME/\//-}
SIMPLE_NAME=${SIMPLE_NAME/:/-}
SIMPLE_NAME=$SIMPLE_NAME-$DOCKER_TARGET_ARCH

# Quick exit if we already have a Docker image downloaded. They are huge!
if [[ -e "$MOBYDIR"/layers-"$SIMPLE_NAME".txt ]]; then
    exit 0
fi

# Run the Moby download script
env TARGETARCH="$DOCKER_TARGET_ARCH" "$FROZEN_SCRIPT" "$MOBYDIR" "$DOCKER_IMAGE"

# dump out the layers in order
[[ ! -e "$MOBYDIR"/manifest.json ]] || jq -r '.[].Layers | .[]' "$MOBYDIR"/manifest.json > "$MOBYDIR"/layers-"$SIMPLE_NAME".txt

# we need to rename manifest.json and repositories so that multiple images can live in the same directory
[[ ! -e "$MOBYDIR"/manifest.json ]] || mv "$MOBYDIR"/manifest.json "$MOBYDIR"/manifest-"$SIMPLE_NAME".json
[[ ! -e "$MOBYDIR"/repositories  ]] || mv "$MOBYDIR"/repositories  "$MOBYDIR"/repositories-"$SIMPLE_NAME"
