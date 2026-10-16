# Evidence: Kubernetes The Hard Way on floci, OrbStack, 2026-10-16

**Host:** macOS arm64, OrbStack 2.2.4 (kernel 7.2.9-orbstack, cgroup v2, Docker 29.8.2), 15 CPUs.
**floci:** built from [allensanborn/floci `kthw/14-imds-after-start`](https://github.com/allensanborn/floci/tree/kthw/14-imds-after-start) (upstream `main` 97b49b56f plus 14 commits).
**KTHW:** [`52eb26d`](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/52eb26dad1a3e9e8083a899bc854421eb4842a73), labs 2 to 12, every `bash` block as written (`test/kthw/plan.json` lists the only skips: lab 3's root-SSH branch, a session switch, and sample output fenced as bash).

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
- nginx answers through its NodePort on both nodes, from the jumpbox (through the tiered security groups)

After the restart: both nodes Ready again, lab 3's hostnames (`server.kubernetes.local` and the nodes) intact, `/var/lib/containerd` mounted from its EBS volume, and containerd, kubelet and kube-proxy active.

## Static checks

`mise run lint`: `terraform fmt` and `validate` clean; tflint 0.64.0 with the AWS ruleset 0.49.0 clean; checkov 3.3.29 with 0 failed checks in all three roots (bootstrap 68 passed, workload 205, account-baseline 65), each of the 16 suppressions inline with its reason.

## Not covered by this run

- Real AWS: not run (no credentials on this machine).
- Docker Desktop, WSL2 and Linux hosts: not run.
- Prowler runtime checks: see `kthw-q85.11`.
