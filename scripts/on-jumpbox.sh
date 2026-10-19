#!/bin/bash
# usage: scripts/on-jumpbox.sh '<command>'   Run a command as root on the jumpbox, through
# EC2 Instance Connect and the endpoint, from the console container.
. "$(dirname "$0")/env.sh"
id=$(aws ec2 describe-instances --filters Name=tag:Name,Values=kthw-jumpbox \
  Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)
mkdir -p "$KTHW_ROOT/.scratch"
printf '%s\n' "$1" > "$KTHW_ROOT/.scratch/on-jumpbox.sh"
exec docker compose -f "$KTHW_ROOT/floci/compose.yaml" --profile "$KTHW_CONSOLE" run --rm -T "$KTHW_CONSOLE" bash -c "
set -e
ssh-keygen -q -t ed25519 -N '' -f /root/k
aws ec2-instance-connect send-ssh-public-key --instance-id $id --instance-os-user admin \
  --ssh-public-key file:///root/k.pub >/dev/null
ssh -q -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -i /root/k \
  -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h' admin@$id \
  'sudo -i bash -s' < /work/.scratch/on-jumpbox.sh" 2> >(grep -v '^ Container' >&2)
