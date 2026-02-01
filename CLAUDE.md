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

### Validation and Preflight
```bash
make preflight                     # Check all dependencies and prerequisites
make verify-images                 # Verify container images are accessible
make validate-machineconfigs       # Validate MachineConfig YAML files
make filter-machineconfigs         # Filter specific flags from MachineConfigs
make clean-complianceremediations  # Reset complianceremediations directory only
```

### Dashboard and Export
```bash
make export-compliance OCP_VERSION=X.XX   # Export compliance data to JSON
make update-dashboard OCP_VERSION=X.XX    # Export and push to trigger dashboard rebuild
make serve-docs                           # Serve Jekyll dashboard locally
make install-jekyll                       # Install Jekyll dependencies
```

## Architecture

### Script Organization
- **`core/`** - Main compliance workflow scripts (install operator, run scans, collect remediations)
- **`utilities/`** - Cleanup and management scripts (delete operator, restart scans, deploy CSI)
- **`modular/`** - Modular MachineConfig tools using `.d` directory includes
- **`lab-tools/`** - BeakerLab-specific utilities (cluster provisioning, kubeconfig fetch)
- **`misc/`** - Helpers (network policies, pull secrets, loopback devices)
- **`scripts/`** - Preflight checks and validation scripts
- **`lib/`** - Shared library functions (`common.sh`)
- **`docs/`** - Jekyll-based compliance dashboard (GitHub Pages)
- **`curated-configs/`** - Curated configuration files

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
- Excluded shellcheck codes: SC1091, SC2034, SC2086, SC2001, SC2028, SC2129, SC2155
- Run `shfmt -w core utilities modular lab-tools misc` to auto-fix formatting

### Python
- Uses `flake8` with ignored rules: E501 (line length), E402 (module import order), W503 (line break before operator)
- Virtual environments (`venv/`, `.venv/`) are excluded from linting

## Requirements
- `oc` (OpenShift CLI) - for cluster operations
- `yq` - YAML processing
- `python3` with dependencies:
  - `pyyaml` - YAML processing
  - `requests` - HTTP library
  - `beautifulsoup4` - HTML parsing
  - `playwright` - Browser automation
- `shellcheck` and `shfmt` - for bash linting
- `jekyll` - for local dashboard development (optional)

## Troubleshooting

### CI Failures in `test-compliance` Workflow

**"Some pods in 'openshift-marketplace' are not Ready" error**

This can occur due to race conditions with the OpenShift marketplace operator's catalog reconciliation. The marketplace operator continuously refreshes catalog source pods, and a new pod might be created right after the readiness check passes. The script now ignores pods created less than 30 seconds ago to avoid this race condition.

If you see this error:
1. Check if the failing pods are very young (a few seconds old) - this indicates the catalog reconciliation race condition
2. The fix is already in place to ignore recently created pods

**CRC cluster startup issues**

When running in GitHub Actions with CRC (CodeReady Containers):
- Ensure `CRC_PULL_SECRET` secret is configured
- CRC requires significant memory (10GB+ configured for CI)
- The cluster may take 15-20 minutes to fully start
- API server connection refused errors during startup are normal

**ProfileBundle not VALID**

The script waits up to 5 minutes for ProfileBundles to become VALID. If they remain in PENDING:
1. Check if profile parser pods have ImagePullBackOff errors
2. Verify the operator version supports your cluster architecture (ARM64 only supported in v1.7.0+)
3. Check for storage issues - the operator needs a working StorageClass

### Analyzing CI Failures

To download and inspect full CI logs:
```bash
# Get run ID from GitHub Actions URL
gh run view <run-id> --repo sebrandon1/compliance-scripts

# Download full logs (not truncated)
gh api repos/sebrandon1/compliance-scripts/actions/runs/<run-id>/logs > logs.zip
unzip logs.zip -d gha-logs

# Search for errors
grep -i "error\|fail" gha-logs/*.txt
```
