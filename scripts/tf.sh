#!/bin/sh
# usage: scripts/tf.sh <bootstrap|account-baseline|workload> <terraform args...>
. "$(dirname "$0")/env.sh"
root=$1; shift
dir=$KTHW_ROOT/$root
if [ "$root" != bootstrap ]; then
  terraform -chdir="$dir" init -input=false -reconfigure -backend-config="$KTHW_BACKEND" >/dev/null
else
  terraform -chdir="$dir" init -input=false >/dev/null
fi
exec terraform -chdir="$dir" "$@"
