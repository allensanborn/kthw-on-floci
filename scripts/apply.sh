#!/bin/sh
# Create or update the KTHW machines (extra arguments go to terraform apply), then
# wait until first boot finishes.
set -e
here=$(dirname "$0")
"$here/tf.sh" workload apply "$@"
"$here/wait-ready.sh"
