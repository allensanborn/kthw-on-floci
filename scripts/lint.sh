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
# The gate above sees only resources written in this repo: checkov does not fetch remote
# modules unless asked, so account-baseline's cloudposse module resources (the trail,
# Config and access-log buckets, the Config role, GuardDuty, Security Hub) are not in it.
# Scan them too, report-only until each finding is fixed or numbered in
# docs/exceptions.md (kthw-q85 bead "triage checkov module findings").
echo "checkov: account-baseline with its modules (report only, does not fail lint)"
checkov --config-file .checkov.yaml -d account-baseline --download-external-modules true \
  --external-modules-download-path "$PWD/.scratch/checkov-modules" --soft-fail \
  | grep -E '^Passed checks' || true
