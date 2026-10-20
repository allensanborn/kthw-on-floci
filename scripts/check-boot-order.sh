#!/bin/sh
# Offline guard: the machines' first boot installs packages from the internet, so
# Terraform must create the NAT gateway and the private subnet's route before any
# machine (4abee99). floci routes nothing, so only the dependency graph shows this.
# `terraform graph` needs an initialised backend, so it runs on a copy with a local one.
set -eu
cd "$(dirname "$0")/.."
src=${1:-workload}
copy=.scratch/graph/$(basename "$src")
rm -rf "$copy" && mkdir -p "$copy"
cp -R "$src"/. "$copy"/
rm -rf "$copy/.terraform" "$copy/tests"
printf 'terraform {\n  backend "local" {}\n}\n' >"$copy/backend_override.tf"
export TF_DATA_DIR="$PWD/$copy/.terraform"
terraform -chdir="$copy" init -input=false >/dev/null
terraform -chdir="$copy" graph | python3 -c '
import re, sys
edges = {}
for a, b in re.findall(r"\"([^\"]+)\" -> \"([^\"]+)\"", sys.stdin.read()):
    edges.setdefault(a, set()).add(b)
def reaches(node, seen=set()):
    for n in edges.get(node, ()):
        if n not in seen:
            seen.add(n)
            reaches(n, seen)
    return seen
deps = reaches("aws_instance.machine")
missing = [r for r in ("aws_nat_gateway.this", "aws_route_table_association.private", "aws_ssm_parameter.ssh_key") if r not in deps]
if missing:
    sys.exit("boot order: aws_instance.machine does not wait for " + ", ".join(missing))
print("boot order: machines wait for the NAT gateway, the private route and their key parameters")
'
