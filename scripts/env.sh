# Sourced by the other scripts: point every AWS client at the chosen target.
# floci is the default; real AWS must be asked for explicitly, so a typo or an
# unset variable can never send a plan to a real account.
set -eu
KTHW_ROOT=$(cd "$(dirname "$0")/.." && pwd)
case "${KTHW_TARGET:-floci}" in
  floci)
    export AWS_ENDPOINT_URL=http://localhost.floci.io:4566
    export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
    export AWS_REGION=${AWS_REGION:-us-east-1}
    unset AWS_PROFILE AWS_SESSION_TOKEN
    KTHW_BACKEND=$KTHW_ROOT/backends/floci.s3.tfbackend
    ;;
  aws)
    unset AWS_ENDPOINT_URL
    KTHW_BACKEND=$KTHW_ROOT/backends/aws.s3.tfbackend
    [ -f "$KTHW_BACKEND" ] || { echo "KTHW_TARGET=aws needs $KTHW_BACKEND (copy the .example)" >&2; exit 1; }
    ;;
  *) echo "KTHW_TARGET must be floci or aws, not '$KTHW_TARGET'" >&2; exit 1 ;;
esac
export AWS_PAGER=
