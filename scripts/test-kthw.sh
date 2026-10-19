#!/bin/bash
# Run all of Kubernetes The Hard Way on the machines (test/kthw/run.py) and keep the log.
. "$(dirname "$0")/env.sh"
set -o pipefail
mkdir -p "$KTHW_ROOT/.scratch"
log=$KTHW_ROOT/.scratch/kthw-run-$(date +%Y%m%d-%H%M%S).log
echo "log: $log"
docker compose -f "$KTHW_ROOT/floci/compose.yaml" --profile "$KTHW_CONSOLE" run --rm -T "$KTHW_CONSOLE" \
  python3 test/kthw/run.py "$@" 2>&1 | tee "$log"
