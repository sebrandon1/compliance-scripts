# Scripts Reference

## Core Workflow (`core/`)

**install-compliance-operator.sh** — Installs the Compliance Operator in `openshift-compliance`. Automatically detects whether storage is available and deploys the HostPath CSI driver if needed.

```bash
./core/install-compliance-operator.sh
./core/install-compliance-operator.sh --co-ref v1.7.0    # Pin to a specific version
CO_REF=v1.8.2 make install-compliance-operator            # Via environment variable
```

After installing, the script waits up to 5 minutes for pods to reach Ready and for ProfileBundles to become `VALID`.

**apply-periodic-scan.sh** — Applies a daily scheduled scan (cron `0 1 * * *`) with custom storage and tolerations, covering E8, CIS, Moderate, and PCI-DSS profiles.

```bash
./core/apply-periodic-scan.sh
```

**create-scan.sh** — Creates an on-demand scan using the built-in `default` ScanSetting.

```bash
./core/create-scan.sh                # Single CIS scan
./core/create-scan.sh --recommended  # All recommended profiles (CIS, Moderate, PCI-DSS)
```

**collect-complianceremediations.sh** — Extracts all remediation YAMLs from the cluster and saves them to `complianceremediations/`.

```bash
./core/collect-complianceremediations.sh
./core/collect-complianceremediations.sh -s high,medium    # Filter by severity
./core/collect-complianceremediations.sh -f                # Fresh run (remove existing output first)
./core/collect-complianceremediations.sh -n my-namespace   # Custom namespace
```

**combine-machineconfigs-by-path.py** — Merges MachineConfigs that target the same file path into combined files.

```bash
python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations
python3 core/combine-machineconfigs-by-path.py --severity high,medium --header provenance --dry-run
```

**organize-machine-configs.sh** — Categorizes MachineConfig YAMLs by topic (sysctl, sshd, audit, etc.).

```bash
./core/organize-machine-configs.sh
./core/organize-machine-configs.sh -d complianceremediations -m /path/to/machineconfigs -s high,medium
./core/organize-machine-configs.sh -x    # Apply configs directly to cluster (use with caution)
```

**generate-compliance-markdown.sh** — Creates a Markdown table mapping ComplianceCheckResults to remediations, sorted by result type.

```bash
./core/generate-compliance-markdown.sh
```

## Utilities (`utilities/`)

**deploy-hostpath-csi.sh** / **delete-hostpath-csi.sh** — Deploy or remove the KubeVirt HostPath CSI driver (same storage provisioner used by CRC).

```bash
./utilities/deploy-hostpath-csi.sh
./utilities/delete-hostpath-csi.sh
```

**delete-compliance-operator.sh** — Removes the operator, its resources, and the `openshift-compliance` namespace.

```bash
./utilities/delete-compliance-operator.sh
```

**delete-scans.sh** — Removes periodic ScanSetting/ScanSettingBinding and associated PVCs.

```bash
./utilities/delete-scans.sh [--namespace NAMESPACE] [--include-cis]
```

**delete-compliancescans.sh** — Deletes ComplianceScan objects, optionally filtering by substring.

```bash
./utilities/delete-compliancescans.sh [--filter SUBSTRING] [--delete-suite] [--delete-ssb]
```

**restart-scans.sh** — Requests re-scan of ComplianceScan resources via annotation.

```bash
./utilities/restart-scans.sh --all
./utilities/restart-scans.sh --scan ocp4-cis --watch
```

**monitor-inprogress-scans.sh** — Dashboard to view scans, suites, pods, PVCs, and events.

```bash
./utilities/monitor-inprogress-scans.sh --watch --interval 10
```

**force-delete-namespace.sh** — Force-deletes a stuck namespace and all its resources.

```bash
./utilities/force-delete-namespace.sh <namespace>
```

## Modular Configuration (`modular/`)

**create-modular-configs.sh** — Creates modular MachineConfig files using `.d` directory includes, allowing per-rule file management.

```bash
./modular/create-modular-configs.sh [-s severity] [-i input-dir] [-o output-dir]
```

**split-machineconfigs-modular.py** — The Python engine behind `create-modular-configs.sh`.

```bash
python3 modular/split-machineconfigs-modular.py --src-dir complianceremediations --out-dir complianceremediations/modular
```

## Miscellaneous (`misc/`)

**generate-network-policies.sh** — Generates default-deny NetworkPolicies for selected namespaces.

```bash
./misc/generate-network-policies.sh                       # Preview only
./misc/generate-network-policies.sh --apply               # Apply to cluster
./misc/generate-network-policies.sh --namespaces ns1,ns2  # Specific namespaces
```

**deploy-loopback-ds.sh** — Deploys a DaemonSet that creates file-backed loop devices on every node. Useful for lab clusters without spare disks.

```bash
./misc/deploy-loopback-ds.sh [--device /dev/loopX] [--size-gib N] [--skip-patch]
```

**replace-pull-secret-credentials.sh** — Updates the cluster-wide pull secret.

```bash
./misc/replace-pull-secret-credentials.sh --pull-secret /path/to/pull-secret.json [--mode merge|replace]
```

**apply-remediations-by-severity.sh** — Applies combined remediation YAMLs for a single severity level.

```bash
./misc/apply-remediations-by-severity.sh <severity>
```

**create-source-comments.py** — Decodes base64 `source:` fields in MachineConfig YAMLs and inserts human-readable comments.

```bash
python3 misc/create-source-comments.py
```

## Lab Tools (`lab-tools/`)

**reprovision-cluster.py** — Reprovisions BeakerLab clusters with a specific OCP version.

```bash
python3 lab-tools/reprovision-cluster.py <OCP_VERSION> --email <EMAIL> --kerberos-id <ID> --env <ENV>
```

**fetch-kubeconfig.py** — Fetches kubeconfig from remote BeakerLab clusters.

```bash
python3 lab-tools/fetch-kubeconfig.py --env cnfdc3 [--wait]
```

**compare-clusters.sh** — Compares two OpenShift clusters to identify permission differences.

```bash
./lab-tools/compare-clusters.sh <crc-kubeconfig> <remote-kubeconfig>
```
