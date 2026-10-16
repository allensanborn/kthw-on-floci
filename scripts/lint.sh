#!/bin/sh
# Static checks for every root. Exit non-zero on any finding not listed in .checkov.yaml.
set -eu
cd "$(dirname "$0")/.."
terraform fmt -recursive -check
tflint --init >/dev/null
for root in bootstrap workload account-baseline; do
  # Its own data directory: linting never touches a root's configured backend or credentials.
  export TF_DATA_DIR="$PWD/.scratch/tf-lint/$root"
  terraform -chdir=$root init -backend=false -input=false >/dev/null
  terraform -chdir=$root validate -no-color
  tflint --chdir=$root --config="$PWD/.tflint.hcl"
done
unset TF_DATA_DIR
for root in bootstrap workload account-baseline; do
  echo "checkov: $root"
  checkov --config-file .checkov.yaml -d "$root"
done
