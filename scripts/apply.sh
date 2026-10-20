#!/bin/sh
# Create or update the KTHW machines (extra arguments go to terraform apply), then
# start any machine the apply left stopped (a replaced volume attachment stops it), and
# wait until first boot finishes.
set -e
here=$(dirname "$0")
"$here/tf.sh" workload apply "$@"
"$here/start-stopped.sh" >/dev/null
"$here/wait-ready.sh"
