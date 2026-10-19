# Gaps

Where this repo on floci differs from the same Terraform on real AWS. Per the project's standing rule, a gap is acceptable only when it is documented and quantified: what differs, how much, what it affects, and how to close it. Every row links its tracking bead in [floci-harness](https://github.com/allensanborn/floci-harness) (`floci-*`); those found by this repo are children of the KTHW epic `floci-5fbo`. Gaps that floci-harness's API sweeps already measure (an error code, a missing field) are not repeated here; this file is for behaviour an API test cannot see.

Status as of 2026-10-16 (bead links 2026-10-19), floci built from the [KTHW stack](https://github.com/allensanborn/floci/tree/18cb970984bfc7255e86103b2558303d72f4079a) (`kthw/01` to `kthw/14`, tip commit `18cb970984bf`, the commit `scripts/floci-image.sh` pins).

## Network

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| Security groups are not enforced inside a VPC (`floci-009`) | Every packet is checked against both sides' rules | Off by default: enforcement mode drops `--privileged`, which kubelet and containerd need (ADR decision 7) | Any instance reaches any port on any other; the tiered groups in `workload/security.tf` are recorded, not applied. 0 of the 16 rules enforced between instances. **Exception:** the EC2 Instance Connect Endpoint tunnel checks the endpoint's egress and the instance's ingress (`kthw/05`). | Enforcement that keeps privileged guests (floci). Meanwhile Prowler and checkov judge the rules from the API, which matches AWS. |
| No VPC routing or NAT (`floci-5fbo.21`) | Private subnets reach the internet only through the NAT gateway in the route table | Instances egress through Docker's default bridge whatever the route tables say; the NAT gateway is a record | Private instances reach the internet with or without the NAT gateway or a `0.0.0.0/0` route. The design is checked on AWS only. | floci VPC routing (not planned). |
| Instances have two extra network interfaces (`floci-5fbo.22`) | One ENI per instance, its VPC address | `eth0` (Docker bridge, default route, publishes SSH), `eth1` (VPC network, the private IP), `eth2` (floci's network, for IMDS and the tunnel) | Anything that picks "the default-route address" gets the Docker bridge address, not the private IP. KTHW is unaffected: kubelet resolves its node name through lab 3's `/etc/hosts`, so both nodes register their private IPs (measured: `10.100.1.20`, `10.100.1.21`). | Route the default via the VPC network, with source routing for published ports (floci). |
| A VPC CIDR already used by any Docker network is substituted (`floci-5fbo.23`) | VPCs may overlap freely | Each VPC is a Docker network; an overlapping CIDR is moved to `10.240.0.0/12` and logged | The instances' private IPs stop matching `machines.txt`. `mise run doctor` fails when `10.100.0.0/16` is taken. | Choose a free `vpc_cidr`. |
| Network ACLs are not enforced (`floci-009`) | Stateless rules on every packet crossing the subnet | Recorded only | The workload's deny-all default NACL (in-VPC traffic and TCP replies only) is not applied; the run on floci does not show whether it lets apt, NTP or GitHub replies back in on AWS (UNVERIFIED; checked on AWS in `kthw-q85.16`). | NACL enforcement (floci). |
| OrbStack does not isolate Docker networks (`floci-wti`) | Separate VPCs and subnets cannot reach each other without routing | floci gives each VPC its own Docker network, but OrbStack (the one tested platform) routes between Docker networks anyway | VPC isolation is addressing only on OrbStack: an instance can reach containers on other floci or Docker networks on the host. | Host limitation (closed as documented); test on Docker Desktop and Linux (`kthw-q85.15`). |

## Compute and storage

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| IMDSv2 is not enforced (`floci-rotj`) | `http_tokens = "required"` rejects IMDSv1 | IMDSv1 still answers | CIS EC2.8 / NIST AC-3 cannot be demonstrated on floci: 4 of 4 instances answer IMDSv1. | Enforce `HttpTokens` per instance (floci). |
| EBS is not encrypted at rest (`floci-5fbo.10`) | `encrypted = true` with the CMK | Recorded only | 6 of 6 volumes report `Encrypted` and the KMS key but hold plain loop files on the Docker host. | dm-crypt per volume (floci, not planned). |
| EBS device names (`floci-5fbo.10`) | Nitro: NVMe, serial = volume id | The requested name (`/dev/xvdf`) | `user_data` mounts whichever of the two exists. | — |
| No EBS hotplug events (`floci-5fbo.10`) | udev sees an attach; `fstab` mounts it | The device node appears without a uevent | `fstab` would not mount `/var/lib/containerd`; a systemd unit in `user_data` does instead. | — |
| EBS device nodes are world-writable; guests see every loop device on the host (`floci-ofh5`) | `brw-rw----` root:disk; an instance sees its own volumes | `brw-rw-rw-`; `lsblk` lists other instances' and other emulators' volumes | A non-root user on a node can read or write both nodes' containerd volumes. Not exploitable from outside the laptop. | `mknod` with 0660/disk (floci); isolation needs unprivileged guests. |
| Launch-time data volumes are dropped (`floci-ue91`) | `ebs_block_device` creates and attaches a volume | Silently ignored | Not used here: `aws_ebs_volume` + `aws_volume_attachment` instead. | Fix in floci. |
| Kernel-global sysctls are the Docker host's (`floci-5fbo.24`) | Each instance has its own kernel | One shared kernel. `net.netfilter.nf_conntrack_max` is read-only in a guest, and kube-proxy (lab 9) exits when it cannot raise it; the guest image gives it a writable copy of that one file | kube-proxy sets 491520 (32768 x 15 cores) and reads it back, but the real limit stays the host's 327680 (measured on OrbStack). Only a node with more than 327680 tracked connections would notice. | Raise the host's limit, or emulate per-instance kernels (not possible with containers). |
| Hostname (`floci-5fbo.25`) | cloud-init sets `ip-10-100-1-20` from IMDS | The container ID | Lab 3 sets the hostnames anyway. | Set the container hostname from the private DNS name (floci). |
| Starting an instance fails if floci's Docker network was recreated (`floci-755y`) | — | `docker compose down` deletes floci's network; the instances stay attached to it and cannot start | `mise run down` uses `docker compose stop`, which keeps it. | Reattach to the current network on start (floci). |
| Running instances lose IMDS when the floci container is recreated (`floci-5fbo.36`) | — | A new floci image makes compose recreate floci; instances that survive it get 404 from IMDS for every path (measured 2026-10-19) | No role credentials and no EC2 Instance Connect keys, so `mise run up` times out after a floci image change. Machines launched after the change are fine. | `mise run destroy` and `apply` after a floci image change; re-register on start (floci). |
| Instances stop when floci stops (`floci-5fbo.26`) | A host reboot does not stop instances | `mise run down` stops them; `mise run up` starts them | Disks (root and EBS) survive; anything not in a systemd unit must be restarted by hand. | — |

## Audit

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| CloudTrail does not deliver to CloudWatch Logs (`floci-5fbo.27`) | Events reach the trail's log group within minutes; the CIS alarms fire from them | The log group and role are recorded (`kthw/11`); nothing is delivered | Prowler `cloudtrail_cloudwatch_logging_enabled` fails on floci (the one unmuted FedRAMP Moderate r4 row, 1 of 191 in the 2026-10-16 run; also the one unmuted NIST 800-53 r5 failure on 2026-10-19). The 16 metric filters and alarms (15 CIS, plus one on the SSH key parameters, E-16) exist but never see an event. | Deliver trail events to the log group (floci). |
| Security Hub evaluates nothing (`floci-5fbo.28`) | Standards run their controls and produce findings | Subscriptions are recorded (`kthw/10`), no controls run | Security Hub shows no findings on floci. Prowler stands in for the evaluation. | — |

## Access

| Gap | AWS | floci | Effect here, quantified | Closing it |
|---|---|---|---|---|
| EC2 Instance Connect trusts Floci's CA (`floci-5fbo.29`) | The signer chain ends at a public root in the AMI | Floci installs its local CA in each guest's trust store | Every guest trusts certificates issued by the key in floci's volume. Dev-machine scope only. | — |
| Instance Connect is authorized by floci's IAM enforcement only (`floci-5fbo.30`) | `ec2-instance-connect:SendSSHPublicKey` with `ec2:osuser` conditions | Allowed unless floci's IAM enforcement is on; `ec2:osuser` is not evaluated | Any local caller can push a key for any user. | Condition keys in floci IAM. |
| The tunnel's SigV4 signature is not verified (`floci-5fbo.31`) | Presigned URL checked | Scope and expiry checked, signature not | Same as above. | — |
| The tunnel needs port 443 and an OS-trusted CA (`floci-5fbo.32`) | Public endpoint, public CA | The AWS CLI dials 443 and trusts only the OS store | Use the console container (`mise run connect`), or publish `127.0.0.1:443` and trust floci's CA on the host. | — |
| SSM `GetParameter` without `WithDecryption` returns a SecureString's plaintext (`floci-5fbo.33`) | The encrypted value, unless the caller asks to decrypt and may use the key | The plaintext (measured 2026-10-19) | The SSH key parameters are SecureString so that only principals allowed the cluster key can read or forge them (E-16); on floci any reader of a parameter sees its value. | Return ciphertext unless `WithDecryption` (floci). |
| SSM `PutParameter --overwrite` may turn a SecureString into a String (`floci-5fbo.34`) | UNVERIFIED here; to confirm on AWS | Allowed; the parameter becomes a String (measured 2026-10-19) | The machines reject a non-SecureString key value, so this is caught here, not exploited. | Match AWS once confirmed (floci). |
| KMS key policies and grants, and S3 bucket policies, are not enforced (`floci-5fbo.35`) | Every KMS and S3 call is checked against them | Stored, not evaluated (reported by the 2026-10-19 Terraform review; not re-measured) | A missing key grant (Config's delivery role) or a wrong source-account deny passes on floci and fails, or leaks, on AWS. Checked on AWS in `kthw-q85.16`. | Policy evaluation for KMS and S3 (floci). |

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
| `kthw/08-systemd-private-cgroupns` | Every systemd guest shared the Docker host's cgroup tree, so the two nodes' kubelets tore down each other's pods (lab 12 crash-looped) |
| `kthw/09-run-instances-ebs-optimized` | `ebs_optimized` was dropped at launch, so every plan replaced the instances |
| `kthw/10-securityhub-standards` | No Security Hub standards subscriptions: CIS, AFSBP and NIST 800-53 could not be enabled |
| `kthw/11-cloudtrail-kms-cloudwatch` | A trail's KMS key and CloudWatch Logs delivery were dropped, so every plan updated the trail |
| `kthw/12-config-recorder-status-persists` | A started Config recorder came back stopped after a floci restart |
| `kthw/13-vpc-network-cleanup-after-restart` | After a floci restart, a deleted VPC's network survived and the next VPC was substituted |
| `kthw/14-imds-after-start` | A started instance lost its link-local IMDS address, so EC2 Instance Connect stopped working after a stop and start |
