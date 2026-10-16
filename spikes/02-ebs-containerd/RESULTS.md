# Spike 02: containerd on a real floci EBS volume

**Beads:** kthw-q85.3, floci-5fbo.1 · **Date:** 2026-10-16 · **Host:** macOS arm64, OrbStack 2.2.4 (same as spike 01) · **floci:** `floci/floci:2.3.0`

## Why

Spike 01 showed that containerd's overlayfs snapshotter can't run a pod container on the guest's overlay root filesystem, and proposed a new per-AMI `volumes:` field in floci. Since floci 2.2.0, attached EBS volumes are real Linux loop devices inside the guest ([floci#4354](https://github.com/floci-io/floci/pull/4354)). If those work, the AWS-native fix is a dedicated EBS data volume at `/var/lib/containerd`, and floci needs no new feature.

## Method

Unlike spike 01, this runs **through floci itself**: floci 2.3.0 in compose, in its own resource namespace (`FLOCI_DOCKER_RESOURCE_NAMESPACE=kthw`, so its containers and volumes can't collide with another floci on the same Docker daemon), with the spike 01 Debian 12 image registered as a systemd AMI through a custom catalog. The test used the AWS CLI: `run-instances`, `create-volume --encrypted` (10 GiB gp3), and `attach-volume /dev/xvdf`. Then [probe.sh](probe.sh) ran inside the guest. Reproduce with [run.sh](run.sh).

## Results

| Step | Result |
|---|---|
| `attach-volume` → `/dev/xvdf` in the guest | ✅ 10 GiB block device (loop-backed) |
| `mkfs.ext4`, mount at `/var/lib/containerd` | ✅ |
| KTHW containerd: start, overlayfs plugin, pull, **run pod container (overlayfs + systemd cgroup)** | ✅ (failed in spike 01 without the volume) |
| Data survives `stop-instances` / `start-instances` | ✅ marker file read back, device node restored by floci |
| `/etc/fstab` entry mounts the volume at boot | ❌ systemd never sees the device: floci creates it with `mknod` after the container starts, and there is no udev in the guest, so no `.device` unit or `/dev/disk/by-label` appears |

## What this changes in the plan

1. **floci-5fbo.1 (per-AMI `volumes:` field) is superseded.** `workload/` gives each node a dedicated encrypted EBS volume (`aws_ebs_volume` + `aws_volume_attachment`) for `/var/lib/containerd`, the same shape as Gruntwork's `persistent_ebs` pattern. Keeping container data off the root volume is also good practice on real AWS.
2. **The guest needs a mount unit that doesn't rely on udev:** a oneshot that waits for the device, runs `mkfs.ext4` only if `blkid` finds no filesystem, and mounts it. The device path differs per target. On AWS Nitro it is `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol<id>`. On floci it is the requested `/dev/xvdf`. The unit tries both. It belongs to the AMI recipe (kthw-q85.3).
3. **floci-5fbo.10 ("EBS is metadata-only") is stale.** It is replaced by the gaps below.

## Floci gaps found (each to be quantified in GAPS.md)

| Gap | AWS | floci 2.3.0 |
|---|---|---|
| Non-root `BlockDeviceMapping` at `RunInstances` | Creates and attaches the extra volume | Silently dropped: only the root volume is recorded, and no device appears |
| Device naming | Nitro: NVMe device, serial = volume id | The requested name (`/dev/xvdf`), Xen-style |
| Device node permissions | `brw-rw----` root:disk | `brw-rw-rw-`: any guest user can read and write the raw disk |
| Block device isolation | An instance sees only its own volumes | A privileged guest sees every loop device on the Docker host, including other floci instances' volumes (observed: another emulator's `loop0`) |
| Block-layer encryption | `Encrypted=true` encrypts at rest | Recorded only; floci's docs state this |
| Hotplug events | udev sees the attach | No uevent, so fstab and `.device` units don't fire (see Results) |

## Not tested

- Docker Desktop, WSL2, Linux (kthw-q85.15).
- Detach while mounted, and `ModifyVolume` resize with a mounted filesystem.
- AWS itself: the Nitro device path in item 2 comes from AWS's EBS NVMe documentation, not from a run (**UNVERIFIED** here).
