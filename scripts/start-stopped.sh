#!/bin/sh
# Start any KTHW machine that is stopped, and wait until all of them run. Prints whether
# there were any machines. Machines stop when floci stops, and on either target when
# Terraform replaces a containerd volume attachment: it stops the machine to detach the
# mounted volume and does not start it again (kthw-q85.31). Waits out the moments after
# a floci restart when it still settles their state (up to 3 minutes).
. "$(dirname "$0")/env.sh"
states() { aws ec2 describe-instances --filters Name=tag:Project,Values=kthw-on-floci \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text; }
had=$(states)
i=0
while [ -n "$had" ]; do
  current=$(states)
  stopped=$(printf '%s\n' "$current" | awk '$2 == "stopped" {print $1}')
  [ -z "$stopped" ] || { aws ec2 start-instances --instance-ids $stopped >/dev/null; echo "starting: $(echo $stopped)" >&2; }
  printf '%s\n' "$current" | awk '$2 != "running" {bad=1} END {exit bad}' && break
  i=$((i + 1)); [ $i -lt 90 ] || { echo "instances did not reach running" >&2; exit 1; }
  sleep 2
done
[ -n "$had" ] && echo machines || echo none
