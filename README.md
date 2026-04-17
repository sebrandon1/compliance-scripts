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

### Fully Automated (Recommended)

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
```

Or run everything in one command:

```bash
make full-workflow
```

Run `make help` to see all available targets. See [Individual Make Targets](#individual-make-targets) for the full list.

### Scan Options

| Option | Command | Schedule | Profiles |
|--------|---------|----------|----------|
| On-demand scan | `./core/create-scan.sh` | Runs once | CIS (default) |
| On-demand, all profiles | `./core/create-scan.sh --recommended` | Runs once | CIS, Moderate, PCI-DSS |
| Periodic scan | `./core/apply-periodic-scan.sh` | Daily (`0 1 * * *`) | E8, CIS, Moderate, PCI-DSS |

### Post-Scan Processing

After scans complete, choose one approach for processing MachineConfigs:

- **Combined** (default, used by `make full-workflow`): `python3 core/combine-machineconfigs-by-path.py` merges remediations targeting the same file path into single files.
- **Modular**: `./modular/create-modular-configs.sh` uses `.d` directory includes for per-rule files. See [MODULAR_APPROACH.md](model-context/MODULAR_APPROACH.md).

Then organize and report:

```bash
./core/organize-machine-configs.sh          # Categorize by topic (sysctl, sshd, etc.)
./core/generate-compliance-markdown.sh      # Create Markdown report of all results
```

## Safety Notes

- **MachineConfig changes trigger rolling node reboots.** Nodes reboot one at a time, which can take 10-45 minutes per pool.
- Use `--dry-run` on `combine-machineconfigs-by-path.py` and `organize-machine-configs.sh` to preview changes before writing files.
- Always review generated YAML before applying to production clusters.
- The `-x` flag on `organize-machine-configs.sh` applies configs directly to the connected cluster.

## Requirements

| Tool | Needed for | Install |
|------|-----------|---------|
| `oc` | All cluster operations | [OpenShift CLI docs](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| `yq` | YAML processing in scripts | `brew install yq` / `go install github.com/mikefarah/yq/v4@latest` |
| `python3` | Combining MachineConfigs, lab tools | Included with most systems |
| `pyyaml` | Python scripts | `pip3 install pyyaml` |
| `requests`, `beautifulsoup4`, `playwright` | Lab tools (`lab-tools/`) | `pip3 install -r requirements.txt` |
| `shellcheck`, `shfmt` | Linting (`make lint`) | `brew install shellcheck shfmt` |
| `flake8` | Python linting | `pip3 install flake8` |
| `jekyll` | Local dashboard dev (`make serve-docs`) | `make install-jekyll` |

Python virtual environment setup:

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
```

## Repository Structure

```
core/               Main compliance workflow scripts
utilities/          Cleanup and management utilities
modular/            Modular MachineConfig tools using .d directory includes
lab-tools/          BeakerLab-specific utilities (provisioning, kubeconfig)
misc/               Helpers (network policies, pull secrets, loopback devices)
scripts/            Preflight checks and validation scripts
lib/                Shared library functions (common.sh)
docs/               Jekyll-based compliance dashboard (GitHub Pages)
curated-configs/    Curated configuration files
model-context/      Documentation for modular MachineConfig design
```

Generated output (git-ignored):
- `complianceremediations/` -- Collected remediation YAMLs
- `generated-networkpolicies/` -- NetworkPolicy YAMLs from preview mode
- `ComplianceCheckResults.md` -- Compliance report
- `created_file_paths.txt` -- List of generated file paths

## Compliance Operator Concepts

The Compliance Operator uses several custom resources to manage scanning:

- **ProfileBundle** -- A bundle of compliance profiles shipped with the operator. Must reach `VALID` status before scans can run.
- **Profile** -- A specific compliance standard (e.g., CIS, E8, Moderate, PCI-DSS) within a ProfileBundle.
- **ScanSetting** -- Defines how to scan: schedule, storage size, tolerations, and roles.
- **ScanSettingBinding** -- Binds Profiles to a ScanSetting, creating the actual scan.
- **ComplianceSuite / ComplianceScan** -- The running scan. Status progresses: `LAUNCHING` -> `RUNNING` -> `DONE`.
- **ComplianceCheckResult** -- Individual pass/fail/manual result for each rule.
- **ComplianceRemediation** -- A remediation object (usually a MachineConfig) that can fix a failing check.
- **MachineConfig** -- An OpenShift resource that configures node-level settings. Applying one triggers a rolling reboot of all nodes in the targeted MachineConfigPool.

## Scripts Reference

### Core Workflow (`core/`)

**install-compliance-operator.sh** -- Installs the Compliance Operator in `openshift-compliance`. Automatically detects whether storage is available and deploys the HostPath CSI driver if needed.

```bash
./core/install-compliance-operator.sh
./core/install-compliance-operator.sh --co-ref v1.7.0    # Pin to a specific version
CO_REF=v1.8.2 make install-compliance-operator            # Via environment variable
```

After installing, the script waits up to 5 minutes for pods to reach Ready and for ProfileBundles to become `VALID`.

**apply-periodic-scan.sh** -- Applies a daily scheduled scan (cron `0 1 * * *`) with custom storage and tolerations, covering E8, CIS, Moderate, and PCI-DSS profiles.

```bash
./core/apply-periodic-scan.sh
```

**create-scan.sh** -- Creates an on-demand scan using the built-in `default` ScanSetting.

```bash
./core/create-scan.sh                # Single CIS scan
./core/create-scan.sh --recommended  # All recommended profiles (CIS, Moderate, PCI-DSS)
```

**collect-complianceremediations.sh** -- Extracts all remediation YAMLs from the cluster and saves them to `complianceremediations/`.

```bash
./core/collect-complianceremediations.sh
./core/collect-complianceremediations.sh -s high,medium    # Filter by severity
./core/collect-complianceremediations.sh -f                # Fresh run (remove existing output first)
./core/collect-complianceremediations.sh -n my-namespace   # Custom namespace
```

**combine-machineconfigs-by-path.py** -- Merges MachineConfigs that target the same file path into combined files.

```bash
python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations
python3 core/combine-machineconfigs-by-path.py --severity high,medium --header provenance --dry-run
```

**organize-machine-configs.sh** -- Categorizes MachineConfig YAMLs by topic (sysctl, sshd, audit, etc.).

```bash
./core/organize-machine-configs.sh
./core/organize-machine-configs.sh -d complianceremediations -m /path/to/machineconfigs -s high,medium
./core/organize-machine-configs.sh -x    # Apply configs directly to cluster (use with caution)
```

**generate-compliance-markdown.sh** -- Creates a Markdown table mapping ComplianceCheckResults to remediations, sorted by result type.

```bash
./core/generate-compliance-markdown.sh
```

### Utilities (`utilities/`)

**deploy-hostpath-csi.sh** / **delete-hostpath-csi.sh** -- Deploy or remove the KubeVirt HostPath CSI driver (same storage provisioner used by CRC).

```bash
./utilities/deploy-hostpath-csi.sh
./utilities/delete-hostpath-csi.sh
```

**delete-compliance-operator.sh** -- Removes the operator, its resources, and the `openshift-compliance` namespace.

```bash
./utilities/delete-compliance-operator.sh
```

**delete-scans.sh** -- Removes periodic ScanSetting/ScanSettingBinding and associated PVCs.

```bash
./utilities/delete-scans.sh [--namespace NAMESPACE] [--include-cis]
```

**delete-compliancescans.sh** -- Deletes ComplianceScan objects, optionally filtering by substring.

```bash
./utilities/delete-compliancescans.sh [--filter SUBSTRING] [--delete-suite] [--delete-ssb]
```

**restart-scans.sh** -- Requests re-scan of ComplianceScan resources via annotation.

```bash
./utilities/restart-scans.sh --all
./utilities/restart-scans.sh --scan ocp4-cis --watch
```

**monitor-inprogress-scans.sh** -- Dashboard to view scans, suites, pods, PVCs, and events.

```bash
./utilities/monitor-inprogress-scans.sh --watch --interval 10
```

**force-delete-namespace.sh** -- Force-deletes a stuck namespace and all its resources.

```bash
./utilities/force-delete-namespace.sh <namespace>
```

### Modular Configuration (`modular/`)

**create-modular-configs.sh** -- Creates modular MachineConfig files using `.d` directory includes, allowing per-rule file management.

```bash
./modular/create-modular-configs.sh [-s severity] [-i input-dir] [-o output-dir]
```

**split-machineconfigs-modular.py** -- The Python engine behind `create-modular-configs.sh`.

```bash
python3 modular/split-machineconfigs-modular.py --src-dir complianceremediations --out-dir complianceremediations/modular
```

### Miscellaneous (`misc/`)

**generate-network-policies.sh** -- Generates default-deny NetworkPolicies for selected namespaces.

```bash
./misc/generate-network-policies.sh                       # Preview only
./misc/generate-network-policies.sh --apply               # Apply to cluster
./misc/generate-network-policies.sh --namespaces ns1,ns2  # Specific namespaces
```

**deploy-loopback-ds.sh** -- Deploys a DaemonSet that creates file-backed loop devices on every node. Useful for lab clusters without spare disks.

```bash
./misc/deploy-loopback-ds.sh [--device /dev/loopX] [--size-gib N] [--skip-patch]
```

**replace-pull-secret-credentials.sh** -- Updates the cluster-wide pull secret.

```bash
./misc/replace-pull-secret-credentials.sh --pull-secret /path/to/pull-secret.json [--mode merge|replace]
```

**apply-remediations-by-severity.sh** -- Applies combined remediation YAMLs for a single severity level.

```bash
./misc/apply-remediations-by-severity.sh <severity>
```

**create-source-comments.py** -- Decodes base64 `source:` fields in MachineConfig YAMLs and inserts human-readable comments.

```bash
python3 misc/create-source-comments.py
```

### Lab Tools (`lab-tools/`)

**reprovision-cluster.py** -- Reprovisions BeakerLab clusters with a specific OCP version.

```bash
python3 lab-tools/reprovision-cluster.py <OCP_VERSION> --email <EMAIL> --kerberos-id <ID> --env <ENV>
```

**fetch-kubeconfig.py** -- Fetches kubeconfig from remote BeakerLab clusters.

```bash
python3 lab-tools/fetch-kubeconfig.py --env cnfdc3 [--wait]
```

**compare-clusters.sh** -- Compares two OpenShift clusters to identify permission differences.

```bash
./lab-tools/compare-clusters.sh <crc-kubeconfig> <remote-kubeconfig>
```

## Individual Make Targets

```bash
# Workflow
make full-workflow                    # Run the entire compliance pipeline
make preflight                        # Check all dependencies

# Installation and scanning
make install-compliance-operator      # Install the operator
make apply-periodic-scan              # Set up daily scans
make create-scan                      # Run an on-demand scan

# Collection and processing
make collect-complianceremediations   # Extract remediations from cluster
make combine-machineconfigs           # Merge overlapping MachineConfigs
make organize-machine-configs         # Categorize by topic
make generate-compliance-markdown     # Generate report

# Validation
make validate-machineconfigs          # Validate MachineConfig YAML files
make filter-machineconfigs            # Filter specific flags (requires INPUT, OUTPUT, FLAGS)
make verify-images                    # Verify container images are accessible
make test-compliance                  # Run full CI validation on local cluster

# Dashboard
make export-compliance OCP_VERSION=4.22   # Export scan data to JSON
make update-dashboard OCP_VERSION=4.22    # Export and push to trigger rebuild
make serve-docs                           # Serve dashboard locally
make install-jekyll                       # Install Jekyll dependencies

# Linting
make lint                             # Run all linters (Python + Bash)
make python-lint                      # Python only (flake8)
make bash-lint                        # Bash only (shellcheck + shfmt)

# Cleanup
make clean                            # Remove generated files
make clean-complianceremediations     # Reset complianceremediations directory
```

## Operator Versioning

There are two distribution channels with different version numbers:

- **Upstream/community** at [ComplianceAsCode/compliance-operator](https://github.com/ComplianceAsCode/compliance-operator), used by the install script's `--co-ref` flag. Supported versions: v1.7.0 and v1.8.2.
- **Red Hat certified**, installed automatically when `redhat-operators` is present in `openshift-marketplace`. Uses its own versioning and is not publicly tagged on GitHub.

The old downstream repo at [openshift/compliance-operator](https://github.com/openshift/compliance-operator) is deprecated.

Upstream images from `ghcr.io/complianceascode` are mirrored to `quay.io/bapalm` for reliability. The install script automatically falls back to the mirror if the upstream tag is unavailable. To manually mirror: `make mirror-images CO_REF=v1.8.2`.

## Troubleshooting

### "Some pods in 'openshift-marketplace' are not Ready"

This can occur due to race conditions with the marketplace operator's catalog reconciliation. The marketplace operator continuously refreshes catalog source pods, and a new pod might appear right after the readiness check passes. The script ignores pods created less than 30 seconds ago to avoid this.

If you see this error, check whether the failing pods are very young (a few seconds old) -- that indicates the race condition, not an actual problem.

### CRC Cluster Startup Issues

When running in GitHub Actions with CRC (CodeReady Containers):
- Ensure the `CRC_PULL_SECRET` secret is configured
- CRC requires significant memory (10GB+ configured for CI)
- The cluster may take 15-20 minutes to fully start
- API server "connection refused" errors during startup are normal

### ProfileBundle Not Reaching VALID Status

The install script waits up to 5 minutes for ProfileBundles to become `VALID`. If they remain in `PENDING`:
1. Check if profile parser pods have ImagePullBackOff errors
2. Verify the operator version supports your cluster architecture (ARM64 only supported in v1.7.0+)
3. Check for storage issues -- the operator needs a working StorageClass

### Downloading Full CI Logs

GitHub Actions truncates log output in the UI. To get complete logs:

```bash
gh run view <run-id> --repo sebrandon1/compliance-scripts
gh api repos/sebrandon1/compliance-scripts/actions/runs/<run-id>/logs > logs.zip
unzip logs.zip -d gha-logs
grep -i "error\|fail" gha-logs/*.txt
```

## Contributing

1. Fork the repo and create a feature branch
2. Run `make lint` before submitting -- CI enforces both Python (flake8) and Bash (shellcheck + shfmt) linting
3. If your change affects the compliance workflow, test with `make test-compliance` against a connected cluster
4. Submit a pull request

## Related Projects

- [Compliance Operator](https://github.com/ComplianceAsCode/compliance-operator) -- The upstream operator
- [Compliance Operator Workshop](https://github.com/ComplianceAsCode/compliance-operator/tree/master/doc/tutorials/workshop/content/exercises) -- Hands-on tutorials
- [Compliance Operator Dashboard](https://github.com/sebrandon1/compliance-operator-dashboard) -- Sister repo: Go + React web UI that reimplements these scripts as a single-binary dashboard
