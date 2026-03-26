# QE Compliance Validation Guide

This guide explains how to use the compliance validation tooling to verify scan results on your own cluster.

## Prerequisites

- `oc` CLI logged into your test cluster
- `jq` installed
- Compliance Operator installed and scans completed

## Quick Start

### 1. Generate a baseline from your cluster

After running compliance scans, capture the current results as your expected baseline:

```bash
make generate-expected OCP_VERSION=4.22
```

This creates `tests/expected-results-4.22.json` with all E8 check results from your cluster.

### 2. Validate results match the baseline

After applying remediations or on a new Z-stream release, re-run scans and validate:

```bash
make validate-compliance EXPECTED=tests/expected-results-4.22.json
```

Output shows:
- **Matching** — results unchanged (expected)
- **REGRESSION** — a check changed status unexpectedly (investigate)
- **MISS** — a check expected but not found (may be notapplicable)

### 3. Use pre-built baselines

We maintain baselines for tested versions:

| File | Version | Checks |
|------|---------|--------|
| `tests/expected-results-4.21.json` | OCP 4.21 | 106 E8 checks |
| `tests/expected-results-4.22.json` | OCP 4.22 | 106 E8 checks |

These are validated nightly in CI against CRC clusters.

## Using with TailoredProfiles

If your cluster uses a TailoredProfile (e.g., `rhcos4-e8-ran-hardened`), the scan may produce different check names or `notapplicable` results. In this case:

1. Generate your own baseline: `make generate-expected OCP_VERSION=4.22`
2. Review the generated JSON — some checks may be missing (notapplicable)
3. Use your custom baseline for validation going forward

## Remediation Group Tracking

Each failing check is mapped to a remediation group. View the full tracking dashboard:

- [OCP 4.22 Groups](https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/)
- [OCP 4.21 Groups](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/)

## Troubleshooting

**"No ComplianceCheckResults found"**
- Ensure scans are complete: `oc get compliancesuite -n openshift-compliance`
- Wait for all suites to show `DONE`

**Many MISS results**
- On SNO clusters, only `worker` role results are produced if using `apply-periodic-scan.sh` (auto-detects SNO)
- Use the nightly workflow's approach to get both roles: create a ScanSetting with both `master` and `worker` roles explicitly

**TailoredProfile shows notapplicable**
- Some OVAL checks don't work with TailoredProfiles (known issue with `no-empty-passwords` and `sshd-disable-empty-passwords`)
- The base `rhcos4-e8` profile produces correct results — use it for validation
