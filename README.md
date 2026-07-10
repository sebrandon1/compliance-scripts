# Hardening Scripts Collection

[![Python Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/python-lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/python-lint.yml)
[![Shell Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml)
[![Test Compliance Operator](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml)

[![OCP 4.22 Compliance](https://img.shields.io/badge/OCP%204.22-34%25%20passing-yellow?style=flat-square&logo=redhatopenshift)](https://sebrandon1.github.io/compliance-scripts/versions/4.22.html)
[![OCP 4.21 Compliance](https://img.shields.io/badge/OCP%204.21-49%25%20passing-yellow?style=flat-square&logo=redhatopenshift)](https://sebrandon1.github.io/compliance-scripts/versions/4.21.html)
[![Remediation Groups](https://img.shields.io/badge/Groups-40%20tracked%20|%2033%20tested-blue?style=flat-square)](https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/)
[![Dashboard](https://img.shields.io/badge/Dashboard-Live-brightgreen?style=flat-square&logo=github)](https://sebrandon1.github.io/compliance-scripts/)

OpenShift clusters must meet compliance standards like CIS, E8, Moderate, and PCI-DSS. The [Compliance Operator](https://github.com/ComplianceAsCode/compliance-operator) scans clusters for violations and generates remediation objects (usually MachineConfigs) to fix them. This repository automates the full workflow: installing the operator, running scans, collecting remediations, merging overlapping MachineConfigs, organizing them by topic, and generating compliance reports. A [live dashboard](https://sebrandon1.github.io/compliance-scripts/) tracks remediation progress across OCP versions.

## Quick Start

```bash
# Install the operator (auto-deploys storage if needed)
./core/install-compliance-operator.sh

# Scan all 4 profiles
./core/create-scan.sh --recommended

# Collect and process results
./core/collect-complianceremediations.sh
python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations
./core/organize-machine-configs.sh
./core/generate-compliance-markdown.sh

# Or run everything in one command
make full-workflow
```

## Guides

| Guide | Description |
|-------|-------------|
| [Scripts Reference](docs/scripts-reference.md) | All scripts with flags, examples, and usage |
| [Make Targets](docs/make-targets.md) | Complete list of Makefile targets |
| [Runbook](docs/RUNBOOK.md) | Step-by-step procedures for onboarding new OCP versions and maintaining compliance tracking |
| [QE Guide](docs/QE-GUIDE.md) | Quality engineering guide for validating scan results and testing remediations |
| [Troubleshooting](docs/troubleshooting.md) | Common issues, CI failures, operator versioning |
| [Modular Approach](model-context/MODULAR_APPROACH.md) | Modular MachineConfig design using `.d` directories |

## Safety Notes

- **MachineConfig changes trigger rolling node reboots.** Nodes reboot one at a time, which can take 10-45 minutes per pool.
- Use `--dry-run` on `combine-machineconfigs-by-path.py` and `organize-machine-configs.sh` to preview changes before writing files.
- Always review generated YAML before applying to production clusters.

## Repository Structure

```
core/               Main compliance workflow scripts
utilities/          Cleanup, management, and image mirroring utilities
modular/            Modular MachineConfig tools using .d directory includes
lab-tools/          BeakerLab-specific utilities (provisioning, kubeconfig)
misc/               Helpers (network policies, pull secrets, loopback devices)
scripts/            Preflight checks, validation, and analysis scripts
tests/              Python unit tests and expected-results baselines
lib/                Shared library functions (common.sh)
docs/               Jekyll-based compliance dashboard (GitHub Pages)
```

## Requirements

| Tool | Needed for | Install |
|------|-----------|---------|
| `oc` | All cluster operations | [OpenShift CLI docs](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| `yq` | YAML processing in scripts | `brew install yq` / `go install github.com/mikefarah/yq/v4@latest` |
| `python3` + `pyyaml` | Combining MachineConfigs | Included with most systems |
| `shellcheck`, `shfmt` | Linting (`make lint`) | `brew install shellcheck shfmt` |

## Development

```bash
make lint              # Run all linters (Python + Bash)
make test-compliance   # Run full CI validation on local cluster
make preflight         # Check all dependencies
make serve-docs        # Serve dashboard locally
```

## Related Projects

- [Compliance Operator](https://github.com/ComplianceAsCode/compliance-operator) — The upstream operator
- [Compliance Operator Dashboard](https://github.com/sebrandon1/compliance-operator-dashboard) — Go + React web UI for compliance management
