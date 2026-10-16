set -u
r(){ n="$1"; shift; if out=$("$@" 2>&1); then echo "PASS  $n"; else echo "FAIL  $n :: $(echo "$out"|tail -2|tr "
" " ")"; fi; }
r "mkfs.ext4 /dev/xvdf" mkfs.ext4 -q -L containerd /dev/xvdf
r "mount at /var/lib/containerd" sh -c 'mkdir -p /var/lib/containerd && mount /dev/xvdf /var/lib/containerd && findmnt -no FSTYPE /var/lib/containerd | grep -x ext4'
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
