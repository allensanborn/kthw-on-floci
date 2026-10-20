#!/bin/bash
# Run all of Kubernetes The Hard Way on the machines (test/kthw/run.py) and keep the log as
# evidence: .scratch/evidence/<UTC time>.log, headed with what it ran on, and its sha256
# printed at the end so a claim can cite the exact log.
. "$(dirname "$0")/env.sh"
set -o pipefail
mkdir -p "$KTHW_ROOT/.scratch/evidence"
log=$KTHW_ROOT/.scratch/evidence/$(date -u +%Y%m%dT%H%M%SZ).log
dirty=$(git -C "$KTHW_ROOT" status --porcelain --untracked-files=no | grep -q . && echo " (dirty)" || true)
{
  echo "kthw-on-floci: $(git -C "$KTHW_ROOT" rev-parse HEAD)$dirty"
  echo "target: ${KTHW_TARGET:-floci}"
  if [ "${KTHW_TARGET:-floci}" = floci ]; then
    rev=$(docker image inspect "${FLOCI_IMAGE:-floci-kthw:dev}" \
      --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true)
    echo "floci image: ${FLOCI_IMAGE:-floci-kthw:dev}, built from allensanborn/floci ${rev:-UNKNOWN (unlabelled image)}"
  fi
  echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"
echo "log: $log"; cat "$log"
status=0
docker compose -f "$KTHW_ROOT/floci/compose.yaml" --profile "$KTHW_CONSOLE" run --no-deps --rm -T "$KTHW_CONSOLE" \
  python3 test/kthw/run.py "$@" 2>&1 | tee -a "$log" || status=$?
echo "finished: $(date -u +%Y-%m-%dT%H:%M:%SZ) exit $status" >> "$log"
echo "log sha256: $(shasum -a 256 "$log" | cut -d' ' -f1)  $log"
exit $status
