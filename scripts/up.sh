#!/bin/sh
# Start floci, wait until it answers, and start any instances a restart stopped.
. "$(dirname "$0")/env.sh"
docker compose -f "$KTHW_ROOT/floci/compose.yaml" up -d
i=0
until aws sts get-caller-identity >/dev/null 2>&1; do
  i=$((i + 1)); [ $i -lt 60 ] || { echo "floci did not answer on $AWS_ENDPOINT_URL" >&2; exit 1; }
  sleep 2
done
stopped=$(aws ec2 describe-instances --filters Name=tag:Project,Values=kthw-on-floci \
  Name=instance-state-name,Values=stopped --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$stopped" ]; then
  aws ec2 start-instances --instance-ids $stopped >/dev/null
  echo "started: $stopped"
fi
echo "floci is up on $AWS_ENDPOINT_URL"
