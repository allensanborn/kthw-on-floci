# Evidence: Kubernetes The Hard Way on floci, OrbStack, 2026-10-16

> **Scope, added 2026-10-19.** "The run" below describes kthw-on-floci tree `bc14781` (its last test:kthw log, `.scratch/kthw-run-20261016-133046.log`, finished 13:32:16 CDT, before `b0f0903` at 13:38) on floci commit `18cb970984bfc7255e86103b2558303d72f4079a`. That commit is the `kthw/14-imds-after-start` tip as of 2026-10-19; the image's commit was not recorded at the time, so the floci commit is inferred, not proven (UNVERIFIED). It predates `b0f0903` (NACLs, the 15 CIS alarms, S3 data events) and every later commit: no test:kthw has run at those trees. The Prowler section describes the `b0f0903` working tree. Local log hashes (the logs are gitignored, so only this machine can check them): `kthw-run-20261016-133046.log` sha256 `5c5321a90bd1d2ae05921f3e81bc148b06470179135f30002dc42a34ba1817cf`; `kthw-run-PASSED.log` (12:26) sha256 `19725c0d40b2251a0ce5edb775e02957994c0fc1d8b741ee0ba2f12746e958e9`. The re-run at HEAD, with commits recorded in the log header by `mise run test:kthw`, is `kthw-q85.22`.

**Host:** macOS arm64, OrbStack 2.2.4 (kernel 7.2.9-orbstack, cgroup v2, Docker 29.8.2), 15 CPUs.
**floci:** built from [allensanborn/floci `kthw/14-imds-after-start`](https://github.com/allensanborn/floci/tree/18cb970984bfc7255e86103b2558303d72f4079a), tip `18cb970984bf` (upstream `main` 97b49b56f plus 14 commits; see the scope note).
**KTHW:** [`52eb26d`](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/52eb26dad1a3e9e8083a899bc854421eb4842a73), labs 2 to 12, every `bash` block as written (`test/kthw/plan.json` lists the only skips: lab 3's root-SSH branch, a session switch, and sample output fenced as bash). The harness also adds commands a learner doesn't type and retries some blocks, all listed in `plan.json`: `before`/`after` hooks in lab 2 (wait until root SSH works; check out the pinned KTHW commit) and lab 3 (`cp /root/machines.txt`), one in lab 12, and up to 600-second retries on 8 blocks in labs 7 to 12 (the way a person waits for a service). Each log above shows 2 retries firing (`(not yet, retrying)`).

## The run

All through the `mise` tasks a learner uses, from an empty workload:

| Step | Result |
|---|---|
| `mise run destroy` (after a floci restart) | 59 destroyed; no VPC network left behind |
| `mise run apply` | 59 added; returned when the jumpbox could SSH to every machine as root |
| `mise run plan` | exit 0: nothing to change |
| `mise run test:kthw` | **PASSED**: every lab, then the checks below |
| `mise run down`, `mise run up` | 4 instances started again, ready |
| `plan` on `account-baseline` and `workload` after the restart | exit 0 for both |

The checks after lab 12, all passed:

- `node-0` and `node-1` Ready, registered with their private IPs (`10.100.1.20`, `10.100.1.21`)
- the lab 12 secret is stored encrypted in etcd (`k8s:enc:aescbc:v1:key1`)
- the nginx pod is Running; port-forward, logs and exec work
- nginx answers through its NodePort on both nodes, from the jumpbox (security groups are not enforced on floci: GAPS.md)

After the restart: both nodes Ready again, lab 3's hostnames (`server.kubernetes.local` and the nodes) intact, `/var/lib/containerd` mounted from its EBS volume, and containerd, kubelet and kube-proxy active.

## Static checks

*Corrected 2026-10-19.* At `bc14781` and `b0f0903`, `mise run lint` did not run in a clean clone (`.checkov.yaml` was not committed until `cebe170`), so the result first written here came from running the checks by hand, and its account-baseline count (65) was wrong. At `cebe170`, `mise run lint`: `terraform fmt` and `validate` clean; tflint 0.64.0 with the AWS ruleset 0.49.0 clean; checkov 3.3.29 with 0 failed checks in all three roots (bootstrap 68 passed, workload 205, account-baseline 67), each of the 16 suppressions inline with its reason. That checkov run covers only resources written in this repo, not the cloudposse modules' resources (see `kthw-q85.19`).

## Runtime compliance (Prowler)

`mise run prowler` (then FedRAMP only): Prowler 5.45.0, `fedramp_moderate_revision_4_aws` (Prowler has no Rev5 FedRAMP framework), us-east-1 only, against floci with `account-baseline` and `workload` applied. 192 findings. Without the mutelist: 181 of 191 requirement rows pass (94.8%). With the documented exceptions muted (`compliance/prowler-mutelist.yaml`, E-12 to E-15): 1 requirement row fails, `cloudtrail_cloudwatch_logging_enabled`, a floci gap (GAPS.md, Audit) that passes on AWS.

Fixed after the first Prowler run, which had 18 failing rows: CloudTrail S3 data events, the 15 CIS section 4 metric filters and alarms (a 16th, not CIS, on the SSH key parameters was added in `5885815`), and deny-all default network ACLs (the workload VPC's now admits only in-VPC traffic and TCP replies).

## Not covered by this run

- Real AWS: not run (no credentials on this machine).
- Docker Desktop, WSL2 and Linux hosts: not run.
- Prowler against real AWS, to compare findings with floci's (ADR decision 17).
