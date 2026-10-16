# Spike 01: can a floci systemd guest run KTHW node components?

**Bead:** kthw-q85.2 · **Date:** 2026-10-15 · **Host:** macOS arm64, OrbStack 2.2.4, kernel `7.2.9-orbstack-00391-g2b298d05fbd4`, cgroup v2, Docker 29.8.2 (overlayfs storage driver)

## Method

Floci's systemd guest image (`floci/ami-ubuntu`) is built locally by floci's AmiImageTool and is not published, so this spike reproduces floci's guest container spec with plain Docker, flag for flag (floci `Ec2ContainerManager.java:659-672`): `--privileged --cgroupns=host --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup`, PID 1 `/sbin/init`. The guest is Debian 12 with systemd ([Dockerfile](Dockerfile)). [probe.sh](probe.sh) runs the KTHW commands that could break inside a container, using KTHW's own pinned versions (containerd 2.1.0-beta.0, runc 1.3.0-rc.1, CNI plugins 1.6.2) and KTHW's `containerd-config.toml` (`snapshotter = "overlayfs"`, `SystemdCgroup = true`). Reproduce with `./run.sh [extra docker run args]`.

This tests the host runtime and the container spec, not floci itself. Floci-level confirmation comes once the Debian AMI is registered through floci's `imageCatalogPath` (kthw-q85.3).

## Results

| KTHW step | Floci spec as-is | Fix | With fix |
|---|---|---|---|
| systemd boots as PID 1 | ✅ `running`, no failed units | — | — |
| Lab 3 `hostnamectl set-hostname` | ❌ `Device or resource busy` | Docker bind-mounts `/etc/hostname` and `/etc/hosts`. At boot: copy each file, `umount` it, write the copy back, then (re)start `systemd-hostnamed`, which runs in its own mount namespace and keeps seeing the old bind until restarted. | ✅ |
| Lab 3 `sed -i … /etc/hosts` | ❌ `cannot rename … Device or resource busy` | same as above | ✅ |
| Lab 9 `apt-get install socat conntrack ipset kmod`, `swapoff -a` | ✅ | — | — |
| Lab 9 `modprobe br-netfilter` | ❌ `Module br-netfilter not found in directory /lib/modules/<kver>` (the module *is* active: `/proc/sys/net/bridge` exists) | Bind the host VM's `/lib/modules` read-only, as kind does. On OrbStack `br_netfilter` is listed in `modules.builtin`, so `modprobe` succeeds. | ✅ |
| Lab 9 `sysctl` bridge-nf-call-iptables, ip_forward | ✅ | — | — |
| Lab 9 containerd starts; overlayfs snapshotter plugin `ok`; image pull | ✅ | — | — |
| Lab 9 **run a pod container** (overlayfs + systemd cgroup) | ❌ `failed to create shim task: failed to mount rootfs component: invalid argument` (overlayfs on top of overlayfs) | A Docker volume at `/var/lib/containerd` (a non-overlay filesystem, as kind does with `/var`) | ✅ |
| Lab 11 `ip route add <pod-cidr> via <node-ip>` | ✅ | — | — |
| EIC identity: `/sys/hypervisor/uuid` or DMI `board_asset_tag` | ❌ neither path exists on arm64 OrbStack (no DMI, no `/sys/hypervisor`), so a file bind has no mountpoint | Overlay mount on `/sys/devices/virtual` (lower = sysfs, upper on tmpfs), then write `dmi/id/board_asset_tag` = instance ID. `/sys/class/net` and `ip link` keep working. | ✅ (manual; not yet wired to the agent) |

## What this changes in the plan

Decision 5 is confirmed: floci needs a per-AMI `volumes:` catalog field, and `/var/lib/containerd` is enough for lab 9. The spike adds three systemd-guest requirements:

1. **Bind `/lib/modules` read-only** into systemd guests (floci change, in the container spec).
2. **Unbind Docker's `/etc/hostname` and `/etc/hosts` at boot**, before `systemd-hostnamed`. Docker's bind mounts are the cause, so the bug probably affects floci's existing Ubuntu cloud guest too (**UNVERIFIED**). A oneshot unit ordered `Before=systemd-hostnamed.service` in the floci-built image is deterministic. A post-start `docker exec` from floci would race systemd.
3. **DMI identity overlay** at boot, written from `AWS_EC2_INSTANCE_ID`, which floci already sets in the guest environment. Also a oneshot unit in the image.

## Not tested here

- The full kubelet + kube-proxy + CNI bridge path (lab 9 end to end). That belongs to the full-KTHW test (kthw-q85.10).
- Docker Desktop, WSL2, Linux (kthw-q85.15). On amd64 hosts `/sys/hypervisor` may exist, and `br_netfilter` may be a loadable module rather than built in.
- Floci's security-group enforcement mode, which drops `--privileged` (decision 3: off by default).
