#!/bin/sh
# Prowler's FedRAMP Moderate checks against the target (floci by default), with the
# documented exceptions muted (compliance/prowler-mutelist.yaml). Reports go to .scratch/prowler.
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
  prowlercloud/prowler:5.45.0 aws --region "$AWS_REGION" \
  --compliance fedramp_moderate_revision_4_aws --mutelist-file /compliance/prowler-mutelist.yaml \
  -M csv --output-directory /home/prowler/output --no-banner
