#!/bin/sh
# Static checks for every root. Exit non-zero on any finding not listed in .checkov.yaml.
set -eu
cd "$(dirname "$0")/.."
terraform fmt -recursive -check
tflint --init >/dev/null
for root in bootstrap workload account-baseline; do
  terraform -chdir=$root init -backend=false -input=false >/dev/null
  terraform -chdir=$root validate -no-color
  tflint --chdir=$root --config="$PWD/.tflint.hcl"
done
checkov --quiet --compact --framework terraform --config-file .checkov.yaml \
  -d bootstrap -d workload -d account-baseline
