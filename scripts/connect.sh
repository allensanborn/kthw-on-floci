#!/bin/sh
# A shell on the jumpbox through the EC2 Instance Connect Endpoint, from the console.
. "$(dirname "$0")/env.sh"
id=$(aws ec2 describe-instances --filters Name=tag:Name,Values=kthw-jumpbox \
  Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)
[ "$id" != None ] || { echo "no running jumpbox; run: mise run apply" >&2; exit 1; }
exec docker compose -f "$KTHW_ROOT/floci/compose.yaml" --profile "$KTHW_CONSOLE" run --rm "$KTHW_CONSOLE" \
  aws ec2-instance-connect ssh --instance-id "$id" --connection-type eice --os-user admin
