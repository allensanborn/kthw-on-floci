#!/bin/sh
# Build floci-kthw:dev from the allensanborn/floci KTHW stack (ADR decision 16), unless
# FLOCI_IMAGE names an image to use instead or one is already built. FLOCI_REF overrides
# the branch; FORCE=1 rebuilds.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
ref=${FLOCI_REF:-kthw/09-run-instances-ebs-optimized}
[ -z "${FLOCI_IMAGE:-}" ] || { echo "using FLOCI_IMAGE=$FLOCI_IMAGE"; exit 0; }
if [ "${FORCE:-0}" != 1 ] && docker image inspect floci-kthw:dev >/dev/null 2>&1; then
  echo "floci-kthw:dev present (FORCE=1 to rebuild from $ref)"; exit 0
fi
src=$root/.scratch/floci
if [ -d "$src/.git" ]; then
  git -C "$src" fetch -q --depth 1 origin "$ref" && git -C "$src" checkout -q FETCH_HEAD
else
  git clone -q --depth 1 --branch "$ref" https://github.com/allensanborn/floci.git "$src"
fi
echo "building floci-kthw:dev from allensanborn/floci $ref ($(git -C "$src" rev-parse --short HEAD)); takes a few minutes"
docker build -q -f "$src/docker/Dockerfile" -t floci-kthw:dev "$src"
