#!/bin/sh
# Build floci-kthw:dev from the allensanborn/floci KTHW stack (ADR decision 16, amended
# 2026-10-19), pinned by commit: the default FLOCI_REF is the stack tip
# (kthw/14-imds-after-start) the evidence ran on. The image is labelled with the commit
# it was built from and rebuilt when that differs, so a stale local image is never reused
# (a branch name as FLOCI_REF therefore rebuilds every time). FLOCI_IMAGE names an image
# to use instead; FORCE=1 rebuilds.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
ref=${FLOCI_REF:-18cb970984bfc7255e86103b2558303d72f4079a}
label=org.opencontainers.image.revision
[ -z "${FLOCI_IMAGE:-}" ] || { echo "using FLOCI_IMAGE=$FLOCI_IMAGE"; exit 0; }
have=$(docker image inspect floci-kthw:dev --format "{{index .Config.Labels \"$label\"}}" 2>/dev/null || true)
if [ "${FORCE:-0}" != 1 ] && [ "$have" = "$ref" ]; then
  echo "floci-kthw:dev present, built from $ref (FORCE=1 to rebuild)"; exit 0
fi
src=$root/.scratch/floci
[ -d "$src/.git" ] || git init -q "$src"
git -C "$src" fetch -q --depth 1 https://github.com/allensanborn/floci.git "$ref"
git -C "$src" checkout -q FETCH_HEAD
rev=$(git -C "$src" rev-parse HEAD)
echo "building floci-kthw:dev from allensanborn/floci $rev (local image: ${have:-unlabelled or none}); the first build takes several minutes"
docker build -q --label "$label=$rev" -f "$src/docker/Dockerfile" -t floci-kthw:dev "$src"
