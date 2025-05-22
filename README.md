# Hardening Scripts Collection

This repository contains a set of scripts to help automate the collection, organization, and management of OpenShift Compliance Operator remediations and related resources.

## Scripts Overview

### 1. install-compliance-operator.sh
Installs the Compliance Operator in the `openshift-compliance` namespace. Waits for the operator to be fully installed and ready.

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
Processes all YAMLs in `complianceremediations/` that are `kind: MachineConfig`, organizes them by topic (e.g., sysctl, sshd), and copies them to the appropriate folder under the ZTP kube-compare reference. Ensures file and metadata names are prefixed with `75-`. Prints out the list of created file paths for easy copy-paste into other manifests.

**Usage:**
```bash
./organize_machine_configs.sh
```

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

**Usage:**
```bash
./create-scan.sh
```

---

### 7. apply-periodic-scan.sh
Applies a periodic ScanSetting and ScanSettingBinding for the `rhcos4-e8` and `ocp4-e8` profiles, as described in the Compliance Operator workshop.

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

## Directory Structure
- `complianceremediations/` — Collected remediation YAMLs (auto-generated, ignored by git)
- `created_file_paths.txt` — List of generated file paths for easy copy-paste
- `ComplianceCheckResults.md` — Markdown report of compliance check results (auto-generated, ignored by git)

---

## Requirements
- `oc` (OpenShift CLI)
- `yq` (YAML processor)

---

## Notes
- Most scripts default to the `openshift-compliance` namespace but allow overriding via arguments.
- Always review generated YAML and Markdown files before applying or merging into production.
