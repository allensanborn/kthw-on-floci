#!/bin/sh
# Start floci, wait until it answers, and start any instances a restart stopped.
. "$(dirname "$0")/env.sh"
docker compose -f "$KTHW_ROOT/floci/compose.yaml" up -d
i=0
until aws sts get-caller-identity >/dev/null 2>&1; do
  i=$((i + 1)); [ $i -lt 60 ] || { echo "floci did not answer on $AWS_ENDPOINT_URL" >&2; exit 1; }
  sleep 2
done
# Instances stop with floci. Start them again, waiting out the moments after a restart
# when floci still settles their state (up to 3 minutes).
states() { aws ec2 describe-instances --filters Name=tag:Project,Values=kthw-on-floci \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text; }
had=$(states)
i=0
while [ -n "$had" ]; do
  current=$(states)
  stopped=$(printf '%s\n' "$current" | awk '$2 == "stopped" {print $1}')
  [ -z "$stopped" ] || { aws ec2 start-instances --instance-ids $stopped >/dev/null; echo "starting: $(echo $stopped)"; }
  printf '%s\n' "$current" | awk '$2 != "running" {bad=1} END {exit bad}' && break
  i=$((i + 1)); [ $i -lt 90 ] || { echo "instances did not reach running" >&2; exit 1; }
  sleep 2
done
if [ -n "$had" ]; then
  "$(dirname "$0")/wait-ready.sh"
fi
echo "floci is up on $AWS_ENDPOINT_URL"
