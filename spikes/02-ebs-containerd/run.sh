#!/bin/sh
# Spike 02: containerd on a real floci EBS volume. Needs the spike 01 image:
#   (cd ../01-node-capability && docker build -t kthw-spike-guest .)
set -eu
cd "$(dirname "$0")"
export AWS_ENDPOINT_URL=http://127.0.0.1:4600 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
  AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=
guest() { docker ps -q --filter "label=io.floci.resource-id=$1"; }

docker compose -p kthw-spike02 up -d
until aws ec2 describe-images --owners self >/dev/null 2>&1; do sleep 2; done

set -- $(aws ec2 run-instances --image-id ami-kthw-debian12 --instance-type t4g.medium \
  --query 'Instances[0].[InstanceId,Placement.AvailabilityZone]' --output text)
IID=$1 AZ=$2
aws ec2 wait instance-running --instance-ids "$IID"
V=$(aws ec2 create-volume --availability-zone "$AZ" --size 10 --volume-type gp3 --encrypted \
  --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids "$V"
aws ec2 attach-volume --volume-id "$V" --instance-id "$IID" --device /dev/xvdf >/dev/null
sleep 3

docker cp probe.sh "$(guest "$IID")":/probe.sh
docker exec "$(guest "$IID")" sh -c 'apt-get -qq update >/dev/null; cd /root && sh /probe.sh'

# Persistence across stop/start
docker exec "$(guest "$IID")" sh -c 'echo kept > /var/lib/containerd/marker; sync'
aws ec2 stop-instances --instance-ids "$IID" >/dev/null && aws ec2 wait instance-stopped --instance-ids "$IID"
aws ec2 start-instances --instance-ids "$IID" >/dev/null && aws ec2 wait instance-running --instance-ids "$IID"
sleep 8
docker exec "$(guest "$IID")" sh -c 'mount /dev/xvdf /var/lib/containerd && cat /var/lib/containerd/marker'

# Gap probe: a non-root BlockDeviceMapping at launch
J=$(aws ec2 run-instances --image-id ami-kthw-debian12 --instance-type t4g.medium \
  --block-device-mappings 'DeviceName=/dev/xvdg,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true}' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$J"
aws ec2 describe-instances --instance-ids "$J" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[].DeviceName' --output text

aws ec2 terminate-instances --instance-ids "$IID" "$J" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$IID" "$J"
docker compose -p kthw-spike02 down
docker volume rm floci-aws-kthw-ec2-volumes
