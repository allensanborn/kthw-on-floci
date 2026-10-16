# Gaps

Where this repo on floci differs from the same Terraform on real AWS. Per the project's standing rule, a gap is acceptable only when it is documented and quantified: what differs, how much, what it affects, and how to close it. Each floci gap links its tracking issue in [floci-harness](https://github.com/allensanborn/floci-harness) (`floci-*`). Gaps that floci-harness's API sweeps already measure (an error code, a missing field) are not repeated here; this file is for behaviour an API test cannot see.

Status as of 2026-10-16, floci built from the [KTHW stack](https://github.com/allensanborn/floci/tree/kthw/07-vpc-network-cleanup) (`kthw/01` to `kthw/07`).

## Network

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| Security groups are not enforced inside a VPC | Every packet is checked against both sides' rules | Off by default: enforcement mode drops `--privileged`, which kubelet and containerd need (ADR decision 7) | Any instance reaches any port on any other; the tiered groups in `workload/security.tf` are recorded, not applied. 0 of the 16 rules enforced between instances. **Exception:** the EC2 Instance Connect Endpoint tunnel checks the endpoint's egress and the instance's ingress (`kthw/05`). | Enforcement that keeps privileged guests (floci). Meanwhile Prowler and checkov judge the rules from the API, which matches AWS. |
| No VPC routing or NAT | Private subnets reach the internet only through the NAT gateway in the route table | Instances egress through Docker's default bridge whatever the route tables say; the NAT gateway is a record | Private instances reach the internet with or without the NAT gateway or a `0.0.0.0/0` route. The design is checked on AWS only. | floci VPC routing (not planned). |
| Instances have two extra network interfaces | One ENI per instance, its VPC address | `eth0` (Docker bridge, default route, publishes SSH), `eth1` (VPC network, the private IP), `eth2` (floci's network, for IMDS and the tunnel) | Anything that picks "the default-route address" picks the Docker bridge address, not the private IP. kubelet does this when no `--node-ip` is set: nodes register a `192.168.x` InternalIP. KTHW still works (lab 11 routes and `/etc/hosts` use the private IPs). | Route the default via the VPC network with source routing for published ports (floci). |
| A VPC CIDR already used by any Docker network is substituted | VPCs may overlap freely | Each VPC is a Docker network; an overlapping CIDR is moved to `10.240.0.0/12` and logged | The instances' private IPs stop matching `machines.txt`. `mise run doctor` fails when `10.100.0.0/16` is taken. | Choose a free `vpc_cidr`. |

## Compute and storage

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| IMDSv2 is not enforced (`floci-rotj`) | `http_tokens = "required"` rejects IMDSv1 | IMDSv1 still answers | CIS EC2.8 / NIST AC-3 cannot be demonstrated on floci: 4 of 4 instances answer IMDSv1. | Enforce `HttpTokens` per instance (floci). |
| EBS is not encrypted at rest | `encrypted = true` with the CMK | Recorded only | 6 of 6 volumes report `Encrypted` and the KMS key but hold plain loop files on the Docker host. | dm-crypt per volume (floci, not planned). |
| EBS device names | Nitro: NVMe, serial = volume id | The requested name (`/dev/xvdf`) | `user_data` mounts whichever of the two exists. | — |
| No EBS hotplug events | udev sees an attach; `fstab` mounts it | The device node appears without a uevent | `fstab` would not mount `/var/lib/containerd`; a systemd unit in `user_data` does instead. | — |
| EBS device nodes are world-writable; guests see every loop device on the host (`floci-ofh5`) | `brw-rw----` root:disk; an instance sees its own volumes | `brw-rw-rw-`; `lsblk` lists other instances' and other emulators' volumes | A non-root user on a node can read or write both nodes' containerd volumes. Not exploitable from outside the laptop. | `mknod` with 0660/disk (floci); isolation needs unprivileged guests. |
| Launch-time data volumes are dropped (`floci-ue91`) | `ebs_block_device` creates and attaches a volume | Silently ignored | Not used here: `aws_ebs_volume` + `aws_volume_attachment` instead. | Fix in floci. |
| Hostname | cloud-init sets `ip-10-100-1-20` from IMDS | The container ID | Lab 3 sets the hostnames anyway. | Set the container hostname from the private DNS name (floci). |
| Instances stop when floci stops | A host reboot does not stop instances | `mise run down` stops them; `mise run up` starts them | Disks (root and EBS) survive; anything not in a systemd unit must be restarted by hand. | — |

## Access

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| EC2 Instance Connect trusts Floci's CA | The signer chain ends at a public root in the AMI | Floci installs its local CA in each guest's trust store | Every guest trusts certificates issued by the key in floci's volume. Dev-machine scope only. | — |
| Instance Connect is authorized by floci's IAM enforcement only | `ec2-instance-connect:SendSSHPublicKey` with `ec2:osuser` conditions | Allowed unless floci's IAM enforcement is on; `ec2:osuser` is not evaluated | Any local caller can push a key for any user. | Condition keys in floci IAM. |
| The tunnel's SigV4 signature is not verified | Presigned URL checked | Scope and expiry checked, signature not | Same as above. | — |
| The tunnel needs port 443 and an OS-trusted CA | Public endpoint, public CA | The AWS CLI dials 443 and trusts only the OS store | Use the console container (`mise run connect`), or publish `127.0.0.1:443` and trust floci's CA on the host. | — |

## Fixed in the floci stack

Found while building this repo and fixed in [allensanborn/floci](https://github.com/allensanborn/floci), each its own branch for an upstream pull request:

| Branch | What was wrong |
|---|---|
| `kthw/01-lib-modules` | `modprobe br_netfilter` failed: no `/lib/modules` in guests |
| `kthw/02-run-instances-private-ip` | `private_ip` ignored; Terraform replaced instances on every apply |
| `kthw/03-systemd-sshd` | A second sshd raced the guest's `ssh.service` |
| `kthw/04-ec2-instance-connect` | No EC2 Instance Connect |
| `kthw/05-ec2-instance-connect-endpoint` | No EC2 Instance Connect Endpoint |
| `kthw/06-terraform-fidelity` | Instance security groups, default-egress revoke, `KmsKeyId`, root volume size and encryption, and flow-log tags did not round-trip, so every plan replaced 8 resources |
| `kthw/07-vpc-network-cleanup` | A deleted VPC's network survived and pushed the next VPC onto a substitute CIDR |
