#!/bin/sh
# Each probe mirrors a KTHW command (lab number in brackets). Prints PASS/FAIL lines.
r() { name="$1"; shift; if out=$("$@" 2>&1); then echo "PASS  $name"; else echo "FAIL  $name :: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi; }
for i in $(seq 1 30); do s=$(systemctl is-system-running 2>/dev/null); case "$s" in running|degraded) break;; esac; sleep 1; done
echo "INFO  systemd state: $s; failed units: $(systemctl --failed --no-legend 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
r "[3] hostnamectl set-hostname node-0" hostnamectl set-hostname node-0
r "[3] hostname now node-0" sh -c 'test "$(hostname)" = node-0'
r "[9] apt install socat conntrack ipset kmod" sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq socat conntrack ipset kmod >/dev/null'
r "[9] swapoff -a" swapoff -a
r "[9] modprobe br-netfilter" modprobe br-netfilter
r "[9] br_netfilter effective (/proc/sys/net/bridge)" test -d /proc/sys/net/bridge
r "[9] sysctl bridge-nf-call-iptables=1" sysctl -w net.bridge.bridge-nf-call-iptables=1
r "[9] sysctl ip_forward=1" sysctl -w net.ipv4.ip_forward=1
r "[11] ip route add 10.200.0.0/24" ip route add 10.200.0.0/24 via "$(ip -4 route show default | awk '{print $3}')"
echo "INFO  /var fs: $(stat -f -c %T /var/lib 2>/dev/null)"
cd /tmp
r "[9] download containerd/runc/cni (KTHW pins)" sh -c '
  curl -fsSLo c.tgz https://github.com/containerd/containerd/releases/download/v2.1.0-beta.0/containerd-2.1.0-beta.0-linux-arm64.tar.gz &&
  curl -fsSLo /usr/local/bin/runc https://github.com/opencontainers/runc/releases/download/v1.3.0-rc.1/runc.arm64 && chmod +x /usr/local/bin/runc &&
  tar -xzf c.tgz -C /usr/local && mkdir -p /opt/cni/bin &&
  curl -fsSL https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-arm64-v1.6.2.tgz | tar -xz -C /opt/cni/bin'
mkdir -p /etc/containerd
cat > /etc/containerd/config.toml <<'T'
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    default_runtime_name = "runc"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
    runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"
T
r "[9] containerd starts (systemd-run unit)" sh -c 'systemd-run --unit=containerd --property=Delegate=yes /usr/local/bin/containerd >/dev/null && sleep 3 && systemctl is-active containerd'
r "[9] overlayfs snapshotter plugin ok" sh -c '/usr/local/bin/ctr plugins ls | grep -E "overlayfs +.* ok"'
r "[9] pull busybox (overlayfs)" /usr/local/bin/ctr images pull docker.io/library/busybox:1.36
r "[9] run container, overlayfs + systemd cgroup" /usr/local/bin/ctr run --rm --snapshotter overlayfs --runc-systemd-cgroup --cgroup "system.slice:kthw:probe1" docker.io/library/busybox:1.36 probe1 echo hello-from-nested
echo "INFO  dmi board_asset_tag: $(cat /sys/devices/virtual/dmi/id/board_asset_tag 2>&1)"
echo "INFO  /etc/hostname mount: $(grep ' /etc/hostname ' /proc/self/mountinfo | awk '{print $4, $5}')"
r "[3] sed -i /etc/hosts (lab 3)" sed -i 's/^127.0.1.1.*/127.0.1.1\tnode-0.kubernetes.local node-0/' /etc/hosts
r "[3-fix] unbind hostname+hosts, restart hostnamed, retry" sh -c 'for f in /etc/hostname /etc/hosts; do cp $f /run/k.$$ && umount $f && cp /run/k.$$ $f; done && systemctl stop systemd-hostnamed && hostnamectl set-hostname node-0 && test "$(cat /etc/hostname)" = node-0 && sed -i "s/^127.0.1.1.*/127.0.1.1\tnode-0/" /etc/hosts'
for p in /sys/hypervisor /sys/devices/virtual/dmi /sys/class/dmi /sys/firmware/dmi; do echo "INFO  exists? $p: $(test -e $p && echo yes || echo no)"; done
r "[eic] tmpfs over /sys/hypervisor + uuid ec2..." sh -c 'mount -t tmpfs -o size=4k,mode=0755 tmpfs /sys/hypervisor && echo ec2e1916-9099-7caf-fd21-012345abcdef > /sys/hypervisor/uuid && test "$(cut -c1-3 /sys/hypervisor/uuid)" = ec2'
