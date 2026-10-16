# Documented exceptions

The project's bar is FedRAMP Moderate (NIST SP 800-53 Rev. 5 Moderate baseline). These are the places where this repo, or the tutorial it serves, deliberately falls short. The standing rule is that a bad practice the tutorial needs stays, for ease, but only with its remediation written down, and a gap is acceptable only when it is documented and quantified.

Floci-vs-AWS differences are a separate list, in [GAPS.md](../GAPS.md). Static-analysis findings suppressed for these reasons carry the exception number in their `#checkov:skip` comment.

## From the tutorial

| # | What | Controls | Scope, quantified | Remediation in production |
|---|---|---|---|---|
| E-1 | Root SSH from the jumpbox to every cluster machine (lab 3) | AC-6, IA-2, AC-17 | 3 machines accept the jumpbox's root key. Keys only: `PasswordAuthentication no` everywhere, and the root key never leaves the jumpbox (only its public half goes through SSM). | Named users with `sudo`, short-lived keys from EC2 Instance Connect or SSM Session Manager, and no direct root login. |
| E-2 | A hand-made certificate authority whose private key sits in `/root/kubernetes-the-hard-way` on the jumpbox and on `server` (lab 4) | SC-12, SC-17 | 1 CA key (RSA 4096), 2 copies on disk, unencrypted; 3653-day certificates. | AWS Private CA or cert-manager with a KMS- or HSM-backed issuer; 1-year or shorter certificates with rotation. |
| E-3 | Client keys and kubeconfigs with embedded keys copied by `scp`, and an encryption key in a file (labs 4 to 6) | IA-5, SC-28 | About 20 private keys on the jumpbox, copies on each machine; `encryption-config.yaml` holds the etcd encryption key in plain text on `server`. | An identity provider (OIDC) for people, short-lived credentials for components, and a KMS provider for etcd encryption. |
| E-4 | Pre-release components: containerd 2.1.0-beta.0, runc 1.3.0-rc.1, etcd 3.6.0-rc.3 (lab 2's downloads list) | SI-2, CM-2 | 3 of the 11 downloaded components are pre-releases. | Released, patched versions from a vetted internal mirror, verified by checksum and signature. |
| E-8 | etcd serves clients over plain HTTP on `127.0.0.1:2379` (lab 7's unit) | SC-8 | Loopback only on `server`; nothing else can reach it. | Mutual TLS for etcd clients and peers. |

## From this repo

| # | What | Controls | Scope, quantified | Remediation in production |
|---|---|---|---|---|
| E-5 | One region: no cross-region replication of the state bucket or the log buckets | CP-6, CP-9 | 4 buckets (state, its access logs, CloudTrail, Config) in one region. | S3 replication to a second region, and Object Lock on audit logs. |
| E-6 | `bootstrap/` keeps local Terraform state | CM-6 | 1 state file, holding bucket and key names only, no secrets. | Create the state bucket from an account-vending pipeline, or migrate this state into the bucket after the first apply. |
| E-7 | GuardDuty runtime monitoring is off | SI-4 | Off for all 4 instances; it installs an agent and is billed per vCPU. S3 and EBS malware protection are on. | Turn on runtime monitoring. |
| E-9 | Cluster members accept all traffic from each other and from the pod range | SC-7 | 1 security group, 4 rules (self and `10.200.0.0/16`, in and out). KTHW's control plane, kubelets and pod routes need these. | Narrow to the ports Kubernetes uses (6443, 10250, 2379-2380, the CNI's), and add network policies inside the cluster. |
| E-10 | Machines reach the internet on TCP 80 and 443 to any address, through the NAT gateway | SC-7(5) | 2 security groups, 4 rules. Needed for Debian packages, GitHub releases and container images. | An egress allowlist (AWS Network Firewall or a proxy) and VPC endpoints for AWS services. |
| E-11 | Instances reach SSM Parameter Store through the NAT gateway | SC-7 | 4 instances, 2 SSM calls each at first boot. | Interface VPC endpoints for SSM. |
| E-12 | The machines run no SSM agent | CM-8, SI-2 | 4 instances not managed by Systems Manager. Access is by EC2 Instance Connect by design. | Install the SSM agent for patching, inventory and Session Manager. |
| E-13 | Security alarms publish to an SNS topic with no subscriber | IR-6, SI-4(5) | 1 topic, 15 alarms. | Subscribe the security team's mail or a SIEM. |
| E-14 | The access-log buckets do not log access to themselves | AU-2 | 3 buckets. Logging a log bucket into itself recurses. | Log them into a separate, central log archive account. |
| E-15 | Bedrock is not covered by CloudTrail data events, and the Config role can read Bedrock configuration | AU-2, AC-6 | Bedrock is not used. The read access comes from the AWS-managed `AWS_ConfigRole` policy. | Add Bedrock data events if Bedrock is adopted. |
