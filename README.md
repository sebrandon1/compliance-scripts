# Hardening Scripts Collection

This repository contains a set of scripts to help automate the collection, organization, and management of OpenShift Compliance Operator remediations and related resources.

- [Compliance Operator GitHub Repository](https://github.com/ComplianceAsCode/compliance-operator)
- [Compliance Operator Workshop Tutorials](https://github.com/ComplianceAsCode/compliance-operator/tree/master/doc/tutorials/workshop/content/exercises)

## Scripts Overview

### 1. install-compliance-operator.sh
Installs the Compliance Operator in the `openshift-compliance` namespace. Waits for the operator to be fully installed and ready.

- [Compliance Operator Install Docs](https://github.com/ComplianceAsCode/compliance-operator#installation)

**Usage:**
```bash
./install-compliance-operator.sh
```

---

### 2. delete-compliance-operator.sh
Deletes the Compliance Operator, its resources, and the `openshift-compliance` namespace.

**Usage:**
```bash
./delete-compliance-operator.sh
```

---

### 3. collect_complianceremediations.sh
Collects all `complianceremediation` objects from the specified namespace (default: `openshift-compliance`), extracts their YAML, and saves them to the `complianceremediations/` directory. Logs totals and types of objects collected.

**Usage:**
```bash
./collect_complianceremediations.sh [namespace]
```

---

### 4. organize_machine_configs.sh
Organizes all YAMLs in a source directory (default: `complianceremediations/`) that are `kind: MachineConfig` by topic (e.g., sysctl, sshd) and copies them to the appropriate destination directory. The script now accepts parameters to override the source and destination directories.

**Usage:**
```bash
./organize-machine-configs.sh -s complianceremediations -m /path/to/machineconfigs -e /path/to/extra-manifests
```
- `-s`  Source directory for YAMLs (default: complianceremediations)
- `-m`  Destination directory for MachineConfigs (default: as set in script)
- `-e`  Destination directory for extra manifests (default: as set in script)
- `-h`  Show help message

If not specified, the script uses the default directory values set at the top of the script.

---

### 5. generate_compliance_markdown.sh
Generates a Markdown report mapping ComplianceCheckResult objects to their corresponding remediation files, including severity and result, sorted by result type.

**Usage:**
```bash
./generate_compliance_markdown.sh
```

---

### 6. create-scan.sh
Creates a basic ScanSettingBinding for the `ocp4-cis` profile in the `openshift-compliance` namespace.

- [Workshop: Creating Your First Scan](https://github.com/ComplianceAsCode/compliance-operator/blob/master/doc/tutorials/workshop/content/exercises/03-creating-your-first-scan.md)

**Usage:**
```bash
./create-scan.sh
```

---

### 7. apply-periodic-scan.sh
Applies a periodic ScanSetting and ScanSettingBinding for the `rhcos4-e8` and `ocp4-e8` profiles, as described in the Compliance Operator workshop.

- [Workshop: Creating Your First Scan (Periodic Example)](https://github.com/ComplianceAsCode/compliance-operator/blob/master/doc/tutorials/workshop/content/exercises/03-creating-your-first-scan.md)

**Usage:**
```bash
./apply-periodic-scan.sh
```

---

### 8. force-delete-namespace.sh
Force deletes a namespace and all its resources (use with caution).

**Usage:**
```bash
./force-delete-namespace.sh <namespace>
```

---

### 9. create-source-comments.py (Optional)
Scans all YAML files in `complianceremediations/` for `kind: MachineConfig` and, for each `source: data:,...` line, decodes the data and inserts a human-readable comment block above the `source:` line. The script is idempotent and will not add duplicate comments.

**Usage:**
```bash
python3 create-source-comments.py
```

---

### 10. combine-machineconfigs-by-path.py
Scans all YAML files in a source directory (default: `complianceremediations/`) for `kind: MachineConfig` and combines any that target the same file path (e.g., `/etc/ssh/sshd_config`) into a single deduplicated YAML. Role distinctions (e.g., master/worker) are ignored unless explicit labels are present in the YAML. Only files with overlapping paths are combined; originals are moved to `combo/` under the source directory if combined. The process is idempotent and only affects files that actually overlap.

**Usage:**
```bash
python3 combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations
```
- `--src-dir`: Source directory containing MachineConfig YAMLs (default: complianceremediations)
- `--out-dir`: Directory to write combined YAMLs (default: complianceremediations)
- Use `-h` or `--help` to see all options.

---

## Python Virtual Environment

It is recommended to use a Python virtual environment when running the Python scripts. To set up a venv and install dependencies:

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install ruamel.yaml
```

---

## Directory Structure
- `complianceremediations/` — Collected remediation YAMLs (auto-generated, ignored by git)
- `created_file_paths.txt` — List of generated file paths for easy copy-paste
- `ComplianceCheckResults.md` — Markdown report of compliance check results (auto-generated, ignored by git)
- `source_comments/` — Directory for storing YAML files with added source comments (see above)

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

This will sequentially run:
- install-compliance-operator.sh
- apply-periodic-scan.sh
- create-scan.sh
- collect-complianceremediations.sh
- organize-machine-configs.sh
- generate-compliance-markdown.sh

### Individual Steps

You can also run each step individually:

```bash
make install-compliance-operator
make apply-periodic-scan
make create-scan
make collect-complianceremediations
make organize-machine-configs
make generate-compliance-markdown
make clean  # Remove generated files
```

See the Makefile for all available targets and details.
