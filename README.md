# Hardening Scripts Collection

[![Python Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/python-lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/python-lint.yml)
[![Shell Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml)
[![Test Compliance Operator](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml)

[![OCP 4.21 Compliance](https://img.shields.io/badge/OCP%204.21-49%25%20passing-yellow?style=flat-square&logo=redhatopenshift)](https://sebrandon1.github.io/compliance-scripts/versions/4.21/4.21.html)
[![Remediation Groups](https://img.shields.io/badge/Groups-17%20tracked-blue?style=flat-square)](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/)
[![Dashboard](https://img.shields.io/badge/Dashboard-Live-brightgreen?style=flat-square&logo=github)](https://sebrandon1.github.io/compliance-scripts/)

This repository contains a set of scripts to help automate the collection, organization, and management of OpenShift Compliance Operator remediations and related resources.

- [Compliance Operator GitHub Repository](https://github.com/ComplianceAsCode/compliance-operator)
- [Compliance Operator Workshop Tutorials](https://github.com/ComplianceAsCode/compliance-operator/tree/master/doc/tutorials/workshop/content/exercises)

## Repository Structure

Scripts are organized into subdirectories:

- **`core/`** - Main compliance workflow scripts
- **`utilities/`** - Cleanup and management utilities
- **`modular/`** - Modular configuration tools
- **`lab-tools/`** - Environment-specific utilities
- **`misc/`** - Miscellaneous helpers

## Quick Start

### Recommended: Single Command (Fully Automated)

```bash
# This handles everything automatically - no prompts needed!
./core/install-compliance-operator.sh
```

The script will:
1. ✅ Check for suitable storage
2. ✅ **Automatically deploy** HostPath CSI if needed (same as CRC uses)
3. ✅ Install Compliance Operator
4. ✅ Wait for everything to be ready

**No user interaction required!** Just run and wait.

Then run scans:
```bash
./core/create-scan.sh           # CIS compliance scan
./core/apply-periodic-scan.sh   # Periodic E8 scans
```

### Alternative: Manual Two-Step

If you prefer to deploy storage manually first:

```bash
./utilities/deploy-hostpath-csi.sh        # Deploy storage (same as CRC)
./core/install-compliance-operator.sh     # Install operator
./core/create-scan.sh                     # Run scans
```

---

## Scripts Overview

### Core Workflow Scripts (`core/`)

These scripts form the main compliance workflow:

#### 1. install-compliance-operator.sh
Installs the Compliance Operator in the `openshift-compliance` namespace. Waits for the operator to be fully installed and ready.

**Fully automated:** The script automatically checks for suitable storage and deploys the HostPath CSI driver if needed - no prompts required!

- [Compliance Operator Install Docs](https://github.com/ComplianceAsCode/compliance-operator#installation)
  - By default this script resolves and uses the latest release tag from the Compliance Operator [releases page](https://github.com/ComplianceAsCode/compliance-operator/releases). If the GitHub API cannot be reached or is rate-limited, it falls back to `master`.

**Usage:**
```bash
./core/install-compliance-operator.sh
```

**Automatic storage detection:**
If no suitable storage is detected, the script will automatically:
- Deploy KubeVirt HostPath CSI driver (same as CRC uses)
- Set it as the default StorageClass
- Continue with operator installation
- No user interaction needed!

**Version pinning and overrides:**

- `--co-ref <ref>`: Force a specific tag/branch for the Compliance Operator manifests (e.g., `v1.7.0`).
- `COMPLIANCE_OPERATOR_REF` env var: Same as `--co-ref`.
- Default when not provided: latest published release tag from GitHub [releases](https://github.com/ComplianceAsCode/compliance-operator/releases).

Examples:
```bash
# Use the latest release (default behavior)
./core/install-compliance-operator.sh

# Pin to a specific release tag
./core/install-compliance-operator.sh --co-ref v1.7.0

# Or via environment variable
COMPLIANCE_OPERATOR_REF=v1.7.0 ./core/install-compliance-operator.sh
```

Readiness behavior:
- After subscribing and installing, the script waits for the operator's non-completed pods in `openshift-compliance` to reach Ready (up to 5 minutes). If not all pods become Ready within the timeout, it prints current pod statuses and continues.

---

#### 2. apply-periodic-scan.sh
Applies a periodic ScanSetting and ScanSettingBinding for the `rhcos4-e8` and `ocp4-e8` profiles.

**Usage:**
```bash
./core/apply-periodic-scan.sh
```

---

#### 3. create-scan.sh
Creates a basic ScanSettingBinding for the `ocp4-cis` profile.

**Usage:**
```bash
./core/create-scan.sh
```

---

#### 4. collect-complianceremediations.sh
Collects all `complianceremediation` objects from the specified namespace (default: `openshift-compliance`), extracts their YAML, and saves them to the `complianceremediations/` directory. Supports optional severity filtering and a fresh run.

**Usage:**
```bash
./core/collect-complianceremediations.sh [-n|--namespace NAMESPACE] [-s|--severity high,medium,low] [-f|--fresh]
```
– `-n, --namespace` Namespace for complianceremediation objects (default: openshift-compliance)
– `-s, --severity` Comma-separated severities to include: high,medium,low
– `-f, --fresh` Remove existing output directory before collecting
– `-h, --help` Show help

---

#### 5. organize-machine-configs.sh
Organizes all YAMLs in a source directory (default: `complianceremediations/`) that are `kind: MachineConfig` by topic (e.g., sysctl, sshd) and copies them to the appropriate destination directory. The script now accepts parameters to override the source and destination directories.

**Usage:**
```bash
./core/organize-machine-configs.sh -d complianceremediations -m /path/to/machineconfigs -e /path/to/extra-manifests -s high,medium,low [-x]
```
- `-d`  Source directory for YAMLs (default: complianceremediations)
- `-m`  Destination directory for MachineConfigs
- `-e`  Destination directory for extra manifests
- `-s`  Comma-separated severities to include (alias: `-S`)
- `-x`  Execute automated apply + health/perf tests for created files
- `-h`  Show help message

If not specified, the script uses the default directory values set at the top of the script.

---

#### 6. generate-compliance-markdown.sh
Generates a Markdown report mapping ComplianceCheckResult objects to their corresponding remediation files, including severity and result, sorted by result type.

**Usage:**
```bash
./core/generate-compliance-markdown.sh
```

---

#### 7. combine-machineconfigs-by-path.py
Scans all YAML files in a source directory for `kind: MachineConfig` and combines any that target the same file path.

**Usage:**
```bash
python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations [--severity high,medium,low] [--header none|provenance|full]
```

---

### Utility Scripts (`utilities/`)

These scripts help manage and clean up compliance resources:

#### 1. deploy-hostpath-csi.sh
Deploys the **KubeVirt HostPath CSI driver** - the same storage provisioner used by CRC.

**Usage:**
```bash
./utilities/deploy-hostpath-csi.sh
```

---

#### 2. delete-compliance-operator.sh
Deletes the Compliance Operator, its resources, and the `openshift-compliance` namespace.

**Usage:**
```bash
./utilities/delete-compliance-operator.sh
```

---

#### 3. delete-scans.sh
Removes the periodic `ScanSetting`/`ScanSettingBinding` and associated PVCs.

**Usage:**
```bash
./utilities/delete-scans.sh [--namespace NAMESPACE] [--include-cis]
```

---

#### 4. delete-compliancescans.sh
Deletes `ComplianceScan` objects, optionally filtering by substring.

**Usage:**
```bash
./utilities/delete-compliancescans.sh [-n|--namespace NAMESPACE] [--filter SUBSTRING] [--delete-suite] [--delete-ssb]
```

---

#### 5. restart-scans.sh
Requests re-scan of one or more `ComplianceScan` resources via annotation.

**Usage:**
```bash
./utilities/restart-scans.sh [--namespace NAMESPACE] [--watch] (--all | --scan NAME [--scan NAME ...] | NAME [NAME ...])
```

---

#### 6. monitor-inprogress-scans.sh
Convenience dashboard to view scans, suites, pods, PVCs, and events.

**Usage:**
```bash
./utilities/monitor-inprogress-scans.sh [-n|--namespace NAMESPACE] [--watch] [--interval SECONDS] [--filter SUBSTRING]
```

---

#### 7. delete-hostpath-csi.sh
Cleans up all resources created by deploy-hostpath-csi.sh.

**Usage:**
```bash
./utilities/delete-hostpath-csi.sh
```

---

#### 8. force-delete-namespace.sh
Force deletes a namespace and all its resources (use with caution).

**Usage:**
```bash
./utilities/force-delete-namespace.sh <namespace>
```

---

### Modular Configuration Tools (`modular/`)

#### 1. split-machineconfigs-modular.py
Creates modular MachineConfig files using `.d` directory includes.

**Usage:**
```bash
python3 modular/split-machineconfigs-modular.py --src-dir complianceremediations --out-dir complianceremediations/modular [-s high,medium,low]
```

---

#### 2. create-modular-configs.sh
User-friendly wrapper script for `split-machineconfigs-modular.py`.

**Usage:**
```bash
./modular/create-modular-configs.sh [-s severity] [-i input-dir] [-o output-dir]
```

---

### Miscellaneous Utilities (`misc/`)

#### 1. generate-network-policies.sh
Generates a default-deny `NetworkPolicy` for selected namespaces. By default, previews YAMLs to `./generated-networkpolicies`. Can apply directly with `--apply`.

**Usage:**
```bash
./misc/generate-network-policies.sh [--apply] [--out-dir DIR] [--exclude-regex REGEX] [--namespaces ns1,ns2]
```
- `--apply` Apply to cluster (default: preview only)
- `--out-dir` Output directory when previewing (default: generated-networkpolicies)
- `--exclude-regex` Regex of namespaces to skip (default excludes system namespaces)
- `--namespaces` Comma-separated explicit namespaces to target
- `-h, --help` Show help

---

#### 2. deploy-loopback-ds.sh
Deploys a privileged DaemonSet on every node that creates and attaches a file-backed loop device (default: `/dev/loop0`) and can optionally patch LVMS `LVMCluster` to reference it. Useful for lab clusters without spare disks.

**Usage:**
```bash
./misc/deploy-loopback-ds.sh [--namespace NS] [--device /dev/loopX] [--size-gib N] [--skip-patch] [--no-auto-detect] [--wait-timeout 300s]
```
- `--namespace` Target namespace for resources (default: `openshift-storage`)
- `--device` Loop device path to target (default: `/dev/loop0`)
- `--size-gib` Backing file size in GiB (default: `10`)
- `--skip-patch` Do not patch LVMS `LVMCluster` after deploy
- `--no-auto-detect` Skip post-rollout device auto-detection
- `--wait-timeout` DaemonSet rollout wait timeout (default: `300s`)

---

#### 3. replace-pull-secret-credentials.sh
Backs up and updates the cluster-wide pull secret in `openshift-config/secret/pull-secret`.

**Usage:**
```bash
./misc/replace-pull-secret-credentials.sh --pull-secret /path/to/pull-secret.json [--kubeconfig /path/to/kubeconfig] [--mode merge|replace]
```

---

#### 4. apply-remediations-by-severity.sh
Applies combined remediation YAMLs for a single severity.

**Usage:**
```bash
./misc/apply-remediations-by-severity.sh <severity>
```

---

#### 5. create-source-comments.py
Scans all YAML files for `kind: MachineConfig` and decodes base64 `source: data:,...` lines, inserting human-readable comments.

**Usage:**
```bash
python3 misc/create-source-comments.py
```

---

### Lab-Specific Tools (`lab-tools/`)

#### 1. reprovision-cluster.py
Reprovisions BeakerLab clusters with a specific OCP version.

**Usage:**
```bash
python3 lab-tools/reprovision-cluster.py <OCP_VERSION> --email <EMAIL> --kerberos-id <ID> --env <ENV>
```

---

#### 2. fetch-kubeconfig.py
Fetches a kubeconfig from remote BeakerLab clusters.

**Usage:**
```bash
python3 lab-tools/fetch-kubeconfig.py --env cnfdc3 [--wait]
```

---

#### 3. compare-clusters.sh
Compares two OpenShift clusters to identify permission differences.

**Usage:**
```bash
./lab-tools/compare-clusters.sh <crc-kubeconfig> <remote-kubeconfig>
```

---

## Documentation

### model-context/
The `model-context/` directory contains comprehensive documentation about the modular MachineConfig implementation:

- **MODULAR_APPROACH.md** - User-facing guide explaining the modular approach, benefits, and usage
- **IMPLEMENTATION_SUMMARY.md** - Technical implementation details and design decisions
- **COMPARISON.md** - Comparison with [PR #439](https://github.com/openshift-kni/telco-reference/pull/439) from telco-reference
- **README.md** - Index and guide for the documentation

This documentation is designed to provide context for AI models, onboarding new developers, and preserving design decisions.

---

## Python Virtual Environment

It is recommended to use a Python virtual environment when running the Python scripts. To set up a venv and install dependencies:

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install pyyaml
```

---

## Directory Structure
- `complianceremediations/` — Collected remediation YAMLs (auto-generated, ignored by git)
- `generated-networkpolicies/` — Generated NetworkPolicy YAMLs (preview mode, ignored by git)
- `created_file_paths.txt` — List of generated file paths (ignored by git)
- `testing-plan.md` — Testing plan generated by organize script
- `ComplianceCheckResults.md` — Markdown report of compliance check results (auto-generated, ignored by git)

---

## Requirements
- `oc` (OpenShift CLI)
- `yq` (YAML processor)
- `python3` (with standard library; no extra packages required)

---

## Notes
- Most scripts default to the `openshift-compliance` namespace but allow overriding via arguments.
- Always review generated YAML and Markdown files before applying or merging into production.

## Automation with Makefile

A `Makefile` is provided to automate the full compliance workflow or run individual steps. This is the recommended way to run the process end-to-end.

### Full Workflow

To run the entire compliance process from install to report generation:

```bash
make full-workflow
```

Recommended order of operations:
- core/install-compliance-operator.sh
- core/apply-periodic-scan.sh
- core/create-scan.sh
- core/collect-complianceremediations.sh
- **Option A (Modular - Recommended):**
  - modular/create-modular-configs.sh         ← creates modular .d directory files
  - core/organize-machine-configs.sh          ← organizes the modular outputs
- **Option B (Combo):**
  - core/combine-machineconfigs-by-path.py    ← combines overlapping MachineConfigs
  - core/organize-machine-configs.sh          ← organizes the combined outputs
- core/generate-compliance-markdown.sh

The `make full-workflow` target runs these steps in order, using the combo approach (Option B) by default.

### Individual Steps

You can also run each step individually:

```bash
make install-compliance-operator
make apply-periodic-scan
make create-scan
make collect-complianceremediations
make combine-machineconfigs
make organize-machine-configs
make generate-compliance-markdown
make clean  # Remove generated files
```

See the Makefile for all available targets and details.
