#!/bin/sh
# Make a Docker-backed floci guest behave like an EC2 instance where KTHW and
# the EC2 Instance Connect agent can tell the difference. Proven in spike 01.
set -eu

# 1. Docker bind-mounts /etc/hostname and /etc/hosts, so hostnamectl and
#    `sed -i /etc/hosts` fail with EBUSY. Replace each bind with a plain file.
for f in /etc/hostname /etc/hosts; do
  if mountpoint -q "$f"; then
    cp "$f" "$f.floci"; umount "$f"; cat "$f.floci" > "$f"; rm -f "$f.floci"
  fi
done

# A stock Debian install maps its own name on 127.0.1.1, and KTHW lab 3's
# `sed 's/^127.0.1.1.*/.../'` edits that line. Docker's generated file lacks it.
grep -q '^127\.0\.1\.1' /etc/hosts || printf '127.0.1.1\t%s\n' "$(hostname)" >> /etc/hosts

# 2. Instance identity: Nitro exposes the instance id as the DMI board asset
#    tag; the EIC agent refuses to run without it. arm64 hosts have no DMI at
#    all, so overlay /sys/devices/virtual (lower = sysfs, upper = tmpfs).
id=$(tr '\0' '\n' < /proc/1/environ | sed -n 's/^AWS_EC2_INSTANCE_ID=//p')
dmi=/sys/devices/virtual/dmi/id
if [ -n "$id" ] && [ "$(cat "$dmi/board_asset_tag" 2>/dev/null)" != "$id" ]; then
  mkdir -p /run/floci-dmi
  mount -t tmpfs tmpfs /run/floci-dmi
  mkdir -p /run/floci-dmi/upper /run/floci-dmi/work
  mount -t overlay overlay \
    -o lowerdir=/sys/devices/virtual,upperdir=/run/floci-dmi/upper,workdir=/run/floci-dmi/work \
    /sys/devices/virtual
  mkdir -p "$dmi"
  printf '%s\n' "$id" > "$dmi/board_asset_tag"
  printf 'Amazon EC2\n' > "$dmi/sys_vendor"
fi

# 3. nf_conntrack_max is global to the kernel, so it is read-only outside the host's
#    network namespace, and kube-proxy (KTHW lab 9) exits when it cannot raise it. Give the
#    guest a writable copy of that one file: the write is absorbed, and the real limit stays
#    the Docker host's (GAPS.md).
ct=/proc/sys/net/netfilter/nf_conntrack_max
if [ -e "$ct" ] && ! [ -w "$ct" ]; then
  cat "$ct" > /run/floci-nf_conntrack_max
  mount --bind /run/floci-nf_conntrack_max "$ct"
fi

# 4. Per-instance SSH host keys (removed from the image at build time).
ssh-keygen -A
