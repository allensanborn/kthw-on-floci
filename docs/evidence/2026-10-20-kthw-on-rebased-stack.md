# Evidence: KTHW on the rebased floci stack (2026-10-20)

Full run after rebasing the floci KTHW stack onto upstream floci and repinning to it, and after the 2026-10-20 fixes (`413deb8` to `25e74de`). Supersedes [2026-10-19](2026-10-19-kthw-at-739fcb5.md).

| | |
|---|---|
| kthw-on-floci | `25e74dedc785849d225dc2af1424adc5b65d1e58` plus the repin (`scripts/floci-image.sh`, `kthw.yml`, `GAPS.md`), which is the commit that adds this file; the log header says "dirty" for that reason |
| floci | `floci-kthw:dev` built by `scripts/floci-image.sh` from allensanborn/floci `cf98d953392a1d27029b4ae047af9f0317cf1893` (`kthw2/18-imds-after-start`, 18 branches on upstream `a89931886`) |
| KTHW | `52eb26dad1a3e9e8083a899bc854421eb4842a73` |
| Host | macOS arm64, OrbStack |
| Test log | `.scratch/evidence/20261020T160729Z.log` (local, gitignored), sha256 `565dc2066fbe1dee7a0cfa92e6d149fe36c19364fca3aae229b5f8a25cdcbde7` |

## What ran, in order (UTC)

1. 16:05 `scripts/tf.sh workload destroy`: 64 destroyed.
2. 16:06 `mise run up`: rebuilt floci from the new pin (the old image's label was `18cb970`), re-created floci.
3. 16:06 `scripts/apply.sh`: 64 added, ready in about a minute.
4. `plan`: no changes.
5. 16:07 to 16:09 `mise run test:kthw`: labs 2 to 12 and the verify checks, **PASSED**.
6. `plan`: no changes.
7. `mise run down`, `mise run up`: ready; workload and account-baseline plans no changes.
8. 16:10 `mise run prowler` (the baseline now includes the per-region detectors, the finding rules and 30-month retention):

| Framework | Fail | Pass | Muted |
|---|---|---|---|
| FedRAMP Moderate Rev4 | 1 | 164 | 78 |
| NIST 800-53 Rev5 | 1 | 169 | 78 |
| CIS 7.0 | 11 | 149 | 0 |

The FedRAMP and NIST failure is `cloudtrail_cloudwatch_logging_enabled`, the floci gap (GAPS.md). CIS 7.0's 11 are the same untriaged set (`kthw-q85.17`). Prowler scanned the home region only.

## Also on 2026-10-20, on floci

- Replacing node-1's containerd volume attachment through `scripts/apply.sh` left the node stopped (the provider's behaviour) and the script started it; ready followed (`kthw-q85.31`).
- The account baseline applied in all 17 default regions (128 resources), GuardDuty, EBS default encryption, Access Analyzer and Config checked in us-west-2, eu-north-1 and ap-south-1.

## Not covered

Real AWS, other platforms and CI: `kthw-q85.16`, `.15`, `.13`.
