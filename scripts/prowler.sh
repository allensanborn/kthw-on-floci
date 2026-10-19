#!/bin/sh
# Prowler against the target (floci by default) with the three frameworks of ADR decision 17:
# FedRAMP Moderate (Prowler has Rev4 only), NIST 800-53 Rev5 and CIS 7.0 (the newest in
# Prowler 5.45), with the documented exceptions muted (compliance/prowler-mutelist.yaml).
# One region: AWS_REGION. Reports go to .scratch/prowler.
. "$(dirname "$0")/env.sh"
out=$KTHW_ROOT/.scratch/prowler
mkdir -p "$out" && chmod 777 "$out"
if [ "${KTHW_TARGET:-floci}" = floci ]; then
  net="--network kthw-floci_default -e AWS_ENDPOINT_URL=http://floci:4566 -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test"
else
  net="-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN"
fi
exec docker run --rm $net -e AWS_DEFAULT_REGION="$AWS_REGION" \
  -v "$out:/home/prowler/output" -v "$KTHW_ROOT/compliance:/compliance:ro" \
  prowlercloud/prowler:5.45.0@sha256:91cbe8cf1fbc8807dd2e389fbe3a0dd822b84697bb868cee1a2bd42bb6db32d7 aws --region "$AWS_REGION" \
  --compliance fedramp_moderate_revision_4_aws nist_800_53_revision_5_aws cis_7.0_aws \
  --mutelist-file /compliance/prowler-mutelist.yaml \
  -M csv --output-directory /home/prowler/output --no-banner
