# kthw-on-floci

Infrastructure for [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) that runs on your laptop through [floci](https://github.com/floci-io/floci), a free local AWS emulator. The same Terraform also applies, unchanged, to real AWS. It's built to a FedRAMP Moderate control bar: private instances, EC2 Instance Connect Endpoint access, IMDSv2, encrypted everything, and an account security baseline.

You run `terraform apply` and get KTHW's four machines (`jumpbox`, `server`, `node-0`, `node-1`). Then you follow Kelsey's tutorial as written.

> **Status: under construction.** Not usable yet. Design: [ADR 0001](docs/adr/0001-kthw-on-floci.md). Latest evidence: [spike 01](spikes/01-node-capability/RESULTS.md).

## Licence

Code in this repo: [Apache-2.0](LICENSE). Kubernetes The Hard Way is © Kelsey Hightower, licensed CC BY-NC-SA 4.0. It's linked here, never copied.
