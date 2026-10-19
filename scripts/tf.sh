#!/bin/sh
# usage: scripts/tf.sh <bootstrap|account-baseline|workload> <terraform args...>
. "$(dirname "$0")/env.sh"
root=$1; shift
dir=$KTHW_ROOT/$root
if [ "$root" != bootstrap ]; then
  terraform -chdir="$dir" init -input=false -reconfigure -backend-config="$KTHW_BACKEND" >/dev/null
else
  # One local state per target: floci keeps the default workspace (terraform.tfstate, the
  # state that exists today, so nothing migrates); aws gets terraform.tfstate.d/aws/.
  # Only here: an exported TF_WORKSPACE would change the S3-backend roots' state keys.
  [ "${KTHW_TARGET:-floci}" != aws ] || export TF_WORKSPACE=aws
  terraform -chdir="$dir" init -input=false >/dev/null
fi
exec terraform -chdir="$dir" "$@"
