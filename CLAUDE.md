# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of shell and Python scripts for automating OpenShift Compliance Operator workflows. The scripts handle installation, scanning, remediation collection, and MachineConfig organization for cluster hardening.

## Common Commands

### Linting
```bash
make lint              # Run all linters (Python + Bash)
make python-lint       # Python only (flake8)
make bash-lint         # Bash only (shellcheck + shfmt)
```

### Testing
```bash
make test-compliance   # Run CI validation on a connected OpenShift cluster
```

### Full Workflow
```bash
make full-workflow     # Execute complete compliance workflow (requires cluster)
```

### Individual Steps
```bash
make install-compliance-operator
make apply-periodic-scan
make create-scan
make collect-complianceremediations
make combine-machineconfigs
make organize-machine-configs
make generate-compliance-markdown
make clean
```

## Architecture

### Script Organization
- **`core/`** - Main compliance workflow scripts (install operator, run scans, collect remediations)
- **`utilities/`** - Cleanup and management scripts (delete operator, restart scans, deploy CSI)
- **`modular/`** - Modular MachineConfig tools using `.d` directory includes
- **`lab-tools/`** - BeakerLab-specific utilities (cluster provisioning, kubeconfig fetch)
- **`misc/`** - Helpers (network policies, pull secrets, loopback devices)

### Key Workflow
1. `install-compliance-operator.sh` - Installs operator, auto-deploys HostPath CSI if needed
2. `apply-periodic-scan.sh` / `create-scan.sh` - Configure and run compliance scans
3. `collect-complianceremediations.sh` - Extract remediation YAMLs from cluster
4. `combine-machineconfigs-by-path.py` - Merge overlapping MachineConfigs
5. `organize-machine-configs.sh` - Categorize by topic (sysctl, sshd, etc.)
6. `generate-compliance-markdown.sh` - Create compliance report

### Python Environment
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Code Style

### Bash
- Scripts use `shellcheck` and `shfmt` for linting
- Excluded shellcheck codes: SC2034, SC2086, SC2001, SC2028, SC2129, SC2155
- Run `shfmt -w core utilities modular lab-tools misc` to auto-fix formatting

### Python
- Uses `flake8` with ignored rules: E501 (line length), E402 (module import order), W503 (line break before operator)
- Virtual environments (`venv/`, `.venv/`) are excluded from linting

## Requirements
- `oc` (OpenShift CLI) - for cluster operations
- `yq` - YAML processing
- `python3` with `pyyaml` - for Python scripts
- `shellcheck` and `shfmt` - for bash linting
