#!/bin/sh
# Can this machine run floci's KTHW machines? Each check names what fails without it.
# Runs its probes in a throwaway container, the way floci runs instances.
set -u
fail=0
check() { name=$1; shift
  if out=$("$@" 2>&1); then echo "ok    $name"; else echo "FAIL  $name: $(echo "$out" | tail -1)"; fail=1; fi; }
probe() { docker run --rm --privileged --cgroupns=host -v /lib/modules:/lib/modules:ro \
  -v /sys/fs/cgroup:/sys/fs/cgroup debian:12 sh -c "$1"; }

check "docker daemon reachable (floci runs instances as containers)" docker info --format '{{.ServerVersion}}'
check "docker compose v2 (floci/compose.yaml)" docker compose version
check "terraform >= 1.10 (S3 native state locking)" sh -c 'terraform version -json | grep -q "\"terraform_version\": \"1\.\(1[0-9]\|[2-9][0-9]\)"'
check "cgroup v2 (systemd guests, containerd SystemdCgroup, lab 9)" probe 'test -f /sys/fs/cgroup/cgroup.controllers'
check "privileged containers (kubelet, containerd in the guest)" probe 'mount -t tmpfs kthw /mnt && umount /mnt'
check "bridge netfilter in the host kernel (lab 9 br-netfilter)" probe \
  'grep -qw br_netfilter /lib/modules/$(uname -r)/modules.builtin || test -e /lib/modules/$(uname -r)/kernel/net/bridge/br_netfilter.ko || test -d /proc/sys/net/bridge'
check "overlayfs in the host kernel (containerd snapshotter, lab 9)" probe 'grep -qw overlay /proc/filesystems'
check "loop devices (EBS volumes for /var/lib/containerd)" probe 'losetup -f'
check "public DNS for *.localhost.floci.io (EC2 Instance Connect Endpoint names)" \
  sh -c 'getent hosts kthw-doctor.localhost.floci.io 2>/dev/null || nslookup kthw-doctor.localhost.floci.io | grep -q 127.0.0.1'
check "nothing else on 10.100.0.0/16 (the VPC must not be substituted)" sh -c \
  '! docker network ls -q | xargs docker network inspect --format "{{range .IPAM.Config}}{{.Subnet}} {{end}}" | tr " " "\n" | grep -qx "10.100.0.0/16"'
[ $fail -eq 0 ] && echo "ready" || { echo "not ready: fix the FAIL lines above (README: Platforms)"; exit 1; }
