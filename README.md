# Hardening Scripts Collection

[![Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/lint.yml)
[![Shell Lint](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/shell-lint.yml)
[![Test Compliance Operator](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml/badge.svg)](https://github.com/sebrandon1/compliance-scripts/actions/workflows/test-compliance.yml)

This repository contains a set of scripts to help automate the collection, organization, and management of OpenShift Compliance Operator remediations and related resources.

- [Compliance Operator GitHub Repository](https://github.com/ComplianceAsCode/compliance-operator)
- [Compliance Operator Workshop Tutorials](https://github.com/ComplianceAsCode/compliance-operator/tree/master/doc/tutorials/workshop/content/exercises)

## Quick Start

### Recommended: Single Command (Fully Automated)

```bash
# This handles everything automatically - no prompts needed!
./install-compliance-operator.sh
```

The script will:
1. ✅ Check for suitable storage
2. ✅ **Automatically deploy** HostPath CSI if needed (same as CRC uses)
3. ✅ Install Compliance Operator
4. ✅ Wait for everything to be ready

**No user interaction required!** Just run and wait.

Then run scans:
```bash
./create-scan.sh           # CIS compliance scan
./apply-periodic-scan.sh   # Periodic E8 scans
```

### Alternative: Manual Two-Step

If you prefer to deploy storage manually first:

```bash
./deploy-hostpath-csi.sh        # Deploy storage (same as CRC)
./install-compliance-operator.sh # Install operator
./create-scan.sh                 # Run scans
```

---

## Scripts Overview

### 1. deploy-hostpath-csi.sh
Deploys the **KubeVirt HostPath CSI driver** - the same storage provisioner used by CRC (Code Ready Containers). This is the **recommended storage solution** for compliance scans.

**Why use this?**
- Handles permissions correctly for `restricted-v2` SCC pods
- Works reliably with SELinux Enforcing
- Same provisioner used by CRC (proven solution)
- No issues with ResultServer writing scan results

**Usage:**
```bash
./deploy-hostpath-csi.sh
```

**What it deploys:**
- Namespace: `hostpath-provisioner`
- CSI Driver: `kubevirt.io.hostpath-provisioner`
- DaemonSet with 4 containers per node
- Default StorageClass: `crc-csi-hostpath-provisioner`

---

### 2. install-compliance-operator.sh
Installs the Compliance Operator in the `openshift-compliance` namespace. Waits for the operator to be fully installed and ready.

**Fully automated:** The script automatically checks for suitable storage and deploys the HostPath CSI driver if needed - no prompts required!

- [Compliance Operator Install Docs](https://github.com/ComplianceAsCode/compliance-operator#installation)
  - By default this script resolves and uses the latest release tag from the Compliance Operator [releases page](https://github.com/ComplianceAsCode/compliance-operator/releases). If the GitHub API cannot be reached or is rate-limited, it falls back to `master`.

**Usage:**
```bash
./install-compliance-operator.sh
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
./install-compliance-operator.sh

# Pin to a specific release tag
./install-compliance-operator.sh --co-ref v1.7.0

# Or via environment variable
COMPLIANCE_OPERATOR_REF=v1.7.0 ./install-compliance-operator.sh
```

Readiness behavior:
- After subscribing and installing, the script waits for the operator's non-completed pods in `openshift-compliance` to reach Ready (up to 5 minutes). If not all pods become Ready within the timeout, it prints current pod statuses and continues.

---

### 3. delete-compliance-operator.sh
Deletes the Compliance Operator, its resources, and the `openshift-compliance` namespace.

**Usage:**
```bash
./delete-compliance-operator.sh
```

---

### 4. collect-complianceremediations.sh
Collects all `complianceremediation` objects from the specified namespace (default: `openshift-compliance`), extracts their YAML, and saves them to the `complianceremediations/` directory. Supports optional severity filtering and a fresh run.

**Usage:**
```bash
./collect-complianceremediations.sh [-n|--namespace NAMESPACE] [-s|--severity high,medium,low] [-f|--fresh]
```
– `-n, --namespace` Namespace for complianceremediation objects (default: openshift-compliance)
– `-s, --severity` Comma-separated severities to include: high,medium,low
– `-f, --fresh` Remove existing output directory before collecting
– `-h, --help` Show help

---

### 5. organize-machine-configs.sh
Organizes all YAMLs in a source directory (default: `complianceremediations/`) that are `kind: MachineConfig` by topic (e.g., sysctl, sshd) and copies them to the appropriate destination directory. The script now accepts parameters to override the source and destination directories.

**Usage:**
```bash
./organize-machine-configs.sh -d complianceremediations -m /path/to/machineconfigs -e /path/to/extra-manifests -s high,medium,low [-x]
```
- `-d`  Source directory for YAMLs (default: complianceremediations)
- `-m`  Destination directory for MachineConfigs
- `-e`  Destination directory for extra manifests
- `-s`  Comma-separated severities to include (alias: `-S`)
- `-x`  Execute automated apply + health/perf tests for created files
- `-h`  Show help message

If not specified, the script uses the default directory values set at the top of the script.

---

### 6. generate-compliance-markdown.sh
Generates a Markdown report mapping ComplianceCheckResult objects to their corresponding remediation files, including severity and result, sorted by result type.

**Usage:**
```bash
./generate-compliance-markdown.sh
```

---

### 7. create-scan.sh
Creates a basic ScanSettingBinding for the `ocp4-cis` profile in the `openshift-compliance` namespace.

- [Workshop: Creating Your First Scan](https://github.com/ComplianceAsCode/compliance-operator/blob/master/doc/tutorials/workshop/content/exercises/03-creating-your-first-scan.md)

**Usage:**
```bash
./create-scan.sh
```

---

### 8. apply-periodic-scan.sh
Applies a periodic ScanSetting and ScanSettingBinding for the `rhcos4-e8` and `ocp4-e8` profiles, as described in the Compliance Operator workshop.

- [Workshop: Creating Your First Scan (Periodic Example)](https://github.com/ComplianceAsCode/compliance-operator/blob/master/doc/tutorials/workshop/content/exercises/03-creating-your-first-scan.md)

**Usage:**
```bash
./apply-periodic-scan.sh
```

---

### 9. generate-network-policies.sh
Generates a default-deny `NetworkPolicy` for selected namespaces. By default, previews YAMLs to `./generated-networkpolicies`. Can apply directly with `--apply`.

**Usage:**
```bash
./generate-network-policies.sh [--apply] [--out-dir DIR] [--exclude-regex REGEX] [--namespaces ns1,ns2]
```
- `--apply` Apply to cluster (default: preview only)
- `--out-dir` Output directory when previewing (default: generated-networkpolicies)
- `--exclude-regex` Regex of namespaces to skip (default excludes system namespaces)
- `--namespaces` Comma-separated explicit namespaces to target
- `-h, --help` Show help

---

### 10. deploy-loopback-ds.sh
Deploys a privileged DaemonSet on every node that creates and attaches a file-backed loop device (default: `/dev/loop0`) and can optionally patch LVMS `LVMCluster` to reference it. Useful for lab clusters without spare disks.

**Usage:**
```bash
./deploy-loopback-ds.sh [--namespace NS] [--device /dev/loopX] [--size-gib N] [--skip-patch] [--no-auto-detect] [--wait-timeout 300s]
```
- `--namespace` Target namespace for resources (default: `openshift-storage`)
- `--device` Loop device path to target (default: `/dev/loop0`)
- `--size-gib` Backing file size in GiB (default: `10`)
- `--skip-patch` Do not patch LVMS `LVMCluster` after deploy
- `--no-auto-detect` Skip post-rollout device auto-detection
- `--wait-timeout` DaemonSet rollout wait timeout (default: `300s`)

---

### 13. delete-scans.sh
Removes the periodic `ScanSetting`/`ScanSettingBinding` (`periodic-setting`/`periodic-e8`) and associated PVCs. Optionally also removes the CIS scan binding/suite.

**Usage:**
```bash
./delete-scans.sh [--namespace NAMESPACE] [--include-cis]
```

---

### 14. delete-compliancescans.sh
Deletes `ComplianceScan` objects, optionally filtering by substring, and optionally deleting related `ComplianceSuite` and `ScanSettingBinding` resources.

**Usage:**
```bash
./delete-compliancescans.sh [-n|--namespace NAMESPACE] [--filter SUBSTRING] [--delete-suite] [--delete-ssb]
```

---

### 15. restart-scans.sh
Requests re-scan of one or more `ComplianceScan` resources via annotation. Can target all scans and optionally watch status.

**Usage:**
```bash
./restart-scans.sh [--namespace NAMESPACE] [--watch] (--all | --scan NAME [--scan NAME ...] | NAME [NAME ...])
```

---

### 16. monitor-inprogress-scans.sh
Convenience dashboard to view default `StorageClass`, scans, suites, pods, PVCs, ProfileBundles, and recent events in the compliance namespace. Supports watch mode, refresh interval, and name filtering.

**Usage:**
```bash
./monitor-inprogress-scans.sh [-n|--namespace NAMESPACE] [--watch] [--interval SECONDS] [--filter SUBSTRING]
```

---

### 17. replace-pull-secret-credentials.sh
Backs up and updates the cluster-wide pull secret in `openshift-config/secret/pull-secret`. Supports `merge` (default) or `replace` modes and optional verification of resulting registries.

**Usage:**
```bash
./replace-pull-secret-credentials.sh --pull-secret /path/to/pull-secret.json [--kubeconfig /path/to/kubeconfig] [--mode merge|replace] [--namespace openshift-config] [--secret-name pull-secret] [--no-verify]
```

---

### 18. fetch-kubeconfig.sh
Fetches a kubeconfig from a remote host via `scp`, writing to a local destination, and sets secure file permissions.

**Usage:**
```bash
./fetch-kubeconfig.sh                        # use defaults
./fetch-kubeconfig.sh <REMOTE_IP>            # custom remote IP
./fetch-kubeconfig.sh <REMOTE_IP> <DEST>     # custom remote IP and destination path
```

---

### 19. apply-remediations-by-severity.sh
Applies combined remediation YAMLs for a single severity (`high|medium|low`). Injects required metadata, performs server-side dry-run first, applies, and waits for reconciliation where appropriate.

**Usage:**
```bash
./apply-remediations-by-severity.sh <severity>
```

---

### 20. force-delete-namespace.sh
Force deletes a namespace and all its resources (use with caution).

**Usage:**
```bash
./force-delete-namespace.sh <namespace>
```

---

### 21. create-source-comments.py (Optional)
Scans all YAML files in `complianceremediations/` for `kind: MachineConfig` and, for each `source: data:,...` line, decodes the data and inserts a human-readable comment block above the `source:` line. The script is idempotent and will not add duplicate comments.

**Usage:**
```bash
python3 create-source-comments.py
```

---

### 22. combine-machineconfigs-by-path.py
Scans all YAML files in a source directory (default: `complianceremediations/`) for `kind: MachineConfig` and combines any that target the same file path (e.g., `/etc/ssh/sshd_config`) into a single deduplicated YAML. Role distinctions (e.g., master/worker) are ignored unless explicit labels are present in the YAML. Only files with overlapping paths are combined; originals are moved to `combo/` under the source directory if combined. The process is idempotent and only affects files that actually overlap.

**Usage:**
```bash
python3 combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations [--severity high,medium,low] [--header none|provenance|full]
```
- `--src-dir` Source directory containing MachineConfig YAMLs (default: complianceremediations)
- `--out-dir` Directory to write combined YAMLs (default: complianceremediations)
- `-s, --severity` Optional comma-separated severities to include
- `--header` Header mode for generated files: `none` (default), `provenance` (one-line), `full` (list sources)

---

### 23. split-machineconfigs-modular.py
Creates modular MachineConfig files using `.d` directory includes for paths that support it (e.g., `/etc/ssh/sshd_config.d/`, `/etc/pam.d/system-auth.d/`). Instead of combining all settings into one monolithic file, this script:

1. Creates a "base" file that enables the `.d` include directory
2. Generates individual modular files for each remediation, placed in the appropriate `.d` directory
3. Makes remediations easier to review, manage, and apply incrementally

This is the **recommended approach** for creating modular, reviewable compliance remediations.

**Usage:**
```bash
python3 split-machineconfigs-modular.py --src-dir complianceremediations --out-dir complianceremediations/modular [-s high,medium,low]
```
- `--src-dir` Source directory containing MachineConfig YAMLs (default: complianceremediations)
- `--out-dir` Directory to write modular YAMLs (default: complianceremediations/modular)
- `-s, --severity` Optional comma-separated severities to include: high, medium, low

**Example Output:**
- `75-sshd_config-base-high.yaml` - Enables `/etc/ssh/sshd_config.d/` include directory
- `76-sshd_config-disable-root-login-worker-high.yaml` - Modular config for PermitRootLogin
- `77-sshd_config-disable-password-auth-worker-high.yaml` - Modular config for PasswordAuthentication

---

### 24. create-modular-configs.sh
User-friendly wrapper script for `split-machineconfigs-modular.py` that simplifies the modular file creation process. This script handles virtual environment activation automatically and provides clear guidance on next steps.

**Usage:**
```bash
./create-modular-configs.sh [-s severity] [-i input-dir] [-o output-dir]
```
- `-s` Severity level(s) to process: high, medium, low (default: high)
- `-i` Input directory for remediation YAMLs (default: complianceremediations)
- `-o` Output directory for modular YAMLs (default: complianceremediations/modular)
- `-h` Show help message

**Examples:**
```bash
# Process high-severity remediations
./create-modular-configs.sh -s high

# Process multiple severity levels
./create-modular-configs.sh -s high,medium

# Custom directories
./create-modular-configs.sh -i custom-input -o custom-output -s high
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
- install-compliance-operator.sh
- apply-periodic-scan.sh
- create-scan.sh
- collect-complianceremediations.sh
- **Option A (Modular - Recommended):**
  - create-modular-configs.sh         ← creates modular .d directory files
  - organize-machine-configs.sh        ← organizes the modular outputs
- **Option B (Combo):**
  - combine-machineconfigs-by-path.py  ← combines overlapping MachineConfigs
  - organize-machine-configs.sh        ← organizes the combined outputs
- generate-compliance-markdown.sh

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
