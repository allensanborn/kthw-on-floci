#!/bin/sh
# Start a guest with exactly floci's systemd-guest spec (floci Ec2ContainerManager.java:659-672):
# --privileged, --cgroupns=host, tmpfs /run + /run/lock, /sys/fs/cgroup bind, /sbin/init.
# Then run probe.sh inside it. Usage: ./run.sh [extra docker run args...]
set -eu
cd "$(dirname "$0")"
docker build -q -t kthw-spike-guest . >/dev/null
docker rm -f kthw-spike >/dev/null 2>&1 || true
docker run -d --name kthw-spike --hostname ip-10-0-1-10 \
  --privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup "$@" kthw-spike-guest >/dev/null
docker cp probe.sh kthw-spike:/probe.sh
docker exec kthw-spike sh /probe.sh
