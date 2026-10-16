# kthw-on-floci

Do [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) (KTHW) on your own computer, on machines built the way a security reviewer would want them built on AWS, without an AWS account.

[floci](https://github.com/floci-io/floci) is a local AWS emulator whose EC2 instances are real Linux machines (Docker containers running systemd). One `terraform apply` creates KTHW's four Debian 12 machines (`jumpbox`, `server`, `node-0`, `node-1`) in a private VPC. You connect with `aws ec2-instance-connect ssh`, as you would on AWS, then follow the tutorial from lab 2 as written. The same Terraform applies unchanged to a real AWS account.

This repo builds infrastructure only. The tutorial is Kelsey Hightower's, and you follow it on his site.

## What you get

```mermaid
flowchart LR
  You["You: mise run connect"] -- "EC2 Instance Connect<br/>(60-second key, IAM-authorized)" --> EICE["Instance Connect Endpoint<br/>10.100.2.0/28"]
  subgraph VPC["VPC 10.100.0.0/16, no public addresses"]
    EICE --> J["jumpbox 10.100.1.4"]
    J -- "root SSH (lab 3)" --> S["server 10.100.1.10"]
    J --> N0["node-0 10.100.1.20"]
    J --> N1["node-1 10.100.1.21"]
  end
```

- **No public addresses and no SSH keys to manage.** The only way in is the EC2 Instance Connect Endpoint, with a key that lives 60 seconds.
- **Lab 3's root SSH, done safely.** The jumpbox's root key reaches the other machines (key only, never a password), `known_hosts` is filled from host keys the machines published themselves, and `/root/machines.txt` is written. Keys are exchanged as public halves through SSM Parameter Store, so no private key is ever in Terraform state.
- **Hardened as for production:** IMDSv2 only, encrypted volumes with a customer-managed KMS key, VPC flow logs, a deny-all default security group, tiered security groups, one least-privilege IAM role per machine, and an account baseline (CloudTrail, AWS Config, GuardDuty, Security Hub with CIS and NIST 800-53).
- **Measured, not assumed.** [GAPS.md](GAPS.md) lists every way floci differs from AWS here, quantified. [docs/exceptions.md](docs/exceptions.md) lists every deliberate departure from FedRAMP Moderate, from the tutorial and from this repo, with its remediation. [docs/adr/0001-kthw-on-floci.md](docs/adr/0001-kthw-on-floci.md) has the reasoning.

## Quick start

You need Docker (OrbStack on macOS is tested), [mise](https://mise.jdx.dev), and about 6 GB of free memory.

```sh
mise trust && mise install   # pinned Terraform, tflint, checkov
mise run doctor              # checks this machine can run the machines
mise run up                  # builds the images and starts floci
mise run bootstrap           # the Terraform state bucket and its KMS key
mise run baseline            # optional: the account security baseline
mise run apply               # the VPC and KTHW's four machines; returns when they are ready
mise run connect             # a shell on the jumpbox
```

On the jumpbox, become root, and start KTHW at [lab 2](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-jumpbox.md):

```sh
sudo -i
```

In [lab 3](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md):

- `machines.txt` is ready: `cp /root/machines.txt ~/kubernetes-the-hard-way/`.
- Root SSH is already enabled, so skip "Enable root SSH Access" and "Generate and Distribute SSH Keys".
- Do the "Hostnames" and "Host Lookup Table" sections as written.

Then follow labs 4 to 12 as written.

To stop for the day, `mise run down`: the machines stop and keep their disks, and `mise run up` starts them again. When you are done, `mise run destroy` deletes them.

## Where the tutorial would fail a review

KTHW optimizes for learning. These steps stay, because the tutorial needs them, each with its remediation in [docs/exceptions.md](docs/exceptions.md):

| KTHW does | Why it fails review | Production does instead |
|---|---|---|
| Root SSH between machines (lab 3) | AC-6 least privilege, IA-2 accountability | Named users with `sudo` and short-lived keys, as you use to reach the jumpbox |
| A hand-made CA whose key sits on the jumpbox (lab 4) | SC-12 key management | A managed CA with KMS- or HSM-backed keys |
| Private keys and kubeconfigs copied with `scp` (labs 4 to 6) | IA-5, SC-28 | Short-lived credentials from an identity provider |
| Pre-release containerd, runc and etcd (lab 2's downloads) | SI-2, CM-2 | Released, patched versions |

## Testing

- `mise run test:kthw` runs the whole tutorial on the machines: every lab's commands as written, from a pinned commit, through the same EC2 Instance Connect path you use. It then checks that both nodes are Ready, that secrets are encrypted in etcd, and that nginx answers through a NodePort on both nodes. This is the project's test that the promise holds, not a way to skip the tutorial.
- `mise run plan` exits 0 when nothing would change; on floci it does right after an apply.
- `mise run prowler` runs Prowler's FedRAMP Moderate checks against the target. On floci, 1 of 191 requirement rows fails, a known floci gap; the [documented exceptions](docs/exceptions.md) are muted by number in `compliance/prowler-mutelist.yaml`.
- `mise run lint` runs `terraform fmt` and `validate`, tflint with the AWS ruleset, and checkov. All three roots pass with no failures; every suppression is written next to its resource with its reason.

## Real AWS

The same roots apply to an AWS account with your credentials. Copy `backends/aws.s3.tfbackend.example` to `backends/aws.s3.tfbackend` and fill it from `bootstrap`'s outputs, then:

```sh
KTHW_TARGET=aws mise run bootstrap
KTHW_TARGET=aws mise run apply
```

This costs money: a NAT gateway, four small instances, KMS keys and, with `baseline`, CloudTrail, Config, GuardDuty and Security Hub. floci is the default target; a real account is used only when `KTHW_TARGET=aws` is set. Not yet run against AWS.

## Platforms

| Platform | Status |
|---|---|
| macOS arm64, OrbStack | Tested |
| macOS, Docker Desktop | Not yet tested |
| Windows, WSL2 | Not yet tested |
| Linux | Not yet tested |

`mise run doctor` names the check a platform fails.

## The floci it runs on

The features this needs are in a stack of branches on [allensanborn/floci](https://github.com/allensanborn/floci), each headed for an upstream pull request ([GAPS.md](GAPS.md#fixed-in-the-floci-stack) lists them). Until a floci release has them all, `floci/compose.yaml` runs an image built from that stack.

## Licence

Apache-2.0 for this repository's code. Kubernetes The Hard Way is © Kelsey Hightower, licensed CC BY-NC-SA 4.0. This repo links to it and never copies it.
