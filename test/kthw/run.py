#!/usr/bin/env python3
"""Run Kubernetes The Hard Way, as written, on kthw-on-floci's machines.

This is the test behind ADR decision 2 ("labs 4-12 work as written"), never
learner automation. It downloads the labs from a pinned KTHW commit (the
tutorial is never vendored), takes each lab's ```bash blocks in order, and runs
them on the jumpbox as root through the same door a learner uses: EC2 Instance
Connect, through the EC2 Instance Connect Endpoint. plan.json says which blocks
run on `server` or a node instead, which are skipped (lab 3's root-SSH branch),
and which a human would wait on (retried).

Run it from the console container (`mise run test:kthw`), with the workload
applied. Exit status is 0 only if every block and every check in plan.json's
"verify" passed.
"""
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
PLAN = json.loads((HERE / "plan.json").read_text())
REPO_DIR = "/root/kubernetes-the-hard-way"
SSH_DIR = pathlib.Path.home() / ".ssh"
KEY = SSH_DIR / "kthw-test"
DELIM = "KTHW_BLOCK_5f0c1d"


def log(message):
    print(f"\n=== {time.strftime('%H:%M:%S')} {message}", flush=True)


def lab_blocks(lab):
    url = (f"https://raw.githubusercontent.com/{PLAN['kthw_repo']}/"
           f"{PLAN['kthw_commit']}/docs/{lab}.md")
    with urllib.request.urlopen(url, timeout=30) as response:
        text = response.read().decode()
    return re.findall(r"```bash\n(.*?)\n```", text, re.S)


def emit(lines, index, body, host=None, retry=None, background=None):
    """One block as bash: eval'd in the lab's shell (keeping its variables), or piped to a node."""
    where = host or "jumpbox"
    lines.append(f'echo; echo "--- [{index}] on {where}"')
    lines.append(f"kthw_block=$(cat <<'{DELIM}'\n{body}\n{DELIM}\n)")
    lines.append('printf "%s\\n" "$kthw_block" | sed "s/^/    /"')
    run = (f'printf "%s\\n" "set -e" "$kthw_block" | ssh -o BatchMode=yes root@{host} bash -s'
           if host else 'eval "$kthw_block"')
    if background:
        lines.append(f"( {run} ) > /root/kthw-bg-{index}.log 2>&1 & kthw_bg+=($!); sleep {background}")
    elif retry:
        lines.append(f"kthw_try {retry} {shlex.quote(run)}")
    else:
        lines.append(run)


def lab_script(entry):
    blocks = lab_blocks(entry["lab"])
    skip = {int(k): v for k, v in entry.get("skip", {}).items()}
    before = {int(k): v for k, v in entry.get("before", {}).items()}
    after = {int(k): v.format(kthw_commit=PLAN["kthw_commit"]) for k, v in entry.get("after", {}).items()}
    retry = {int(k): v for k, v in entry.get("retry", {}).items()}
    background = {int(k): v for k, v in entry.get("background", {}).items()}
    remote = entry.get("remote", [])
    starts = {r["from"] for r in remote}

    lines = [
        "set -e -o pipefail",
        "export DEBIAN_FRONTEND=noninteractive SYSTEMD_PAGER=cat PAGER=cat",
        f"cd {REPO_DIR} 2>/dev/null || cd /root",
        "kthw_bg=()",
        "trap 'for p in \"${kthw_bg[@]}\"; do kill $p 2>/dev/null || true; done' EXIT",
        # Retry a block the way a person waits for a service: until it passes or time runs out.
        'kthw_try() { local end=$((SECONDS + $1)); until eval "$2"; do '
        '(( SECONDS < end )) || return 1; echo "    (not yet, retrying)"; sleep 5; done; }',
    ]
    i = 0
    while i < len(blocks):
        if i in starts:
            group = [r for r in remote if r["from"] == i]
            for r in group:
                for j in range(r["from"], r["to"] + 1):
                    if j not in skip:
                        emit(lines, j, blocks[j], host=r["host"], retry=retry.get(j))
            i = max(r["to"] for r in group) + 1
            continue
        if i in before:
            lines.append(f'echo "--- (test harness) {before[i]}"; {before[i]}')
        if i in skip:
            lines.append(f'echo; echo "--- [{i}] skipped: {skip[i]}"')
        else:
            emit(lines, i, blocks[i], retry=retry.get(i), background=background.get(i))
        if i in after:
            lines.append(f'echo "--- (test harness) {after[i]}"; {after[i]}')
        i += 1
    return "\n".join(lines) + "\n"


class Jumpbox:
    """An SSH ControlMaster to the jumpbox through the EC2 Instance Connect Endpoint."""

    def __init__(self, instance_id):
        self.instance_id = instance_id
        self.base = ["ssh", "-o", f"ControlPath={SSH_DIR}/cm-%C", "-o", "ControlMaster=auto",
                     "-o", "ControlPersist=50m", "-o", "ServerAliveInterval=30",
                     "-o", "StrictHostKeyChecking=accept-new", "-o", f"UserKnownHostsFile={SSH_DIR}/known_hosts",
                     "-o", "ProxyCommand=aws ec2-instance-connect open-tunnel --instance-id %h",
                     "-i", str(KEY), f"admin@{instance_id}"]

    def connect(self):
        if subprocess.run(self.base[:4] + ["-O", "check"] + self.base[-1:], capture_output=True).returncode == 0:
            return
        if not KEY.exists():
            SSH_DIR.mkdir(mode=0o700, exist_ok=True)
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(KEY)], check=True)
        # The pushed key is good for 60 seconds: long enough to open the master connection.
        subprocess.run(["aws", "ec2-instance-connect", "send-ssh-public-key", "--instance-id", self.instance_id,
                        "--instance-os-user", "admin", "--ssh-public-key", f"file://{KEY}.pub"],
                       check=True, capture_output=True)
        subprocess.run(self.base + ["true"], check=True)

    def run_as_root(self, script, name):
        self.connect()
        subprocess.run(self.base + [f"sudo install -d -m 0700 /root/kthw && sudo tee /root/kthw/{name} >/dev/null"],
                       input=script.encode(), check=True)
        # From a file with stdin closed: lab commands such as `ssh root@host cmd` read stdin.
        return subprocess.run(self.base + [f"sudo -i bash /root/kthw/{name} < /dev/null"]).returncode


def main():
    instance_id = os.environ.get("KTHW_JUMPBOX_ID") or subprocess.run(
        ["aws", "ec2", "describe-instances", "--filters", "Name=tag:Name,Values=kthw-jumpbox",
         "Name=instance-state-name,Values=running", "--query", "Reservations[0].Instances[0].InstanceId",
         "--output", "text"], check=True, capture_output=True, text=True).stdout.strip()
    jumpbox = Jumpbox(instance_id)
    log(f"KTHW {PLAN['kthw_commit'][:12]} on jumpbox {instance_id}")
    only = sys.argv[1:]
    for entry in PLAN["labs"]:
        if only and not any(entry["lab"].startswith(prefix) for prefix in only):
            continue
        log(f"lab {entry['lab']}")
        status = jumpbox.run_as_root(lab_script(entry), entry["lab"] + ".sh")
        if status != 0:
            log(f"FAILED in lab {entry['lab']} (exit {status})")
            return 1
    log("verify")
    checks = "\n".join(["set -e", f"cd {REPO_DIR}"] +
                       [f'echo "check: {shlex.quote(c)[1:-1]}"; {c}' for c in PLAN["verify"]])
    status = jumpbox.run_as_root(checks + "\n", "verify.sh")
    log("PASSED: Kubernetes The Hard Way ran as written" if status == 0 else f"FAILED verify (exit {status})")
    return status


if __name__ == "__main__":
    sys.exit(main())
