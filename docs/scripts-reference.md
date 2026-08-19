# Scripts Reference

## Core Workflow (`core/`)

**install-compliance-operator.sh** — Installs the Compliance Operator in `openshift-compliance`. Automatically detects whether storage is available and deploys the HostPath CSI driver if needed.

```bash
./core/install-compliance-operator.sh
./core/install-compliance-operator.sh --co-ref v1.9.0    # Pin to a specific version
CO_REF=v1.9.0 make install-compliance-operator            # Via environment variable
```

After installing, the script waits up to 5 minutes for pods to reach Ready and for ProfileBundles to become `VALID`.

**apply-periodic-scan.sh** — Applies a daily scheduled scan (cron `0 1 * * *`) with custom storage and tolerations, covering E8, CIS, Moderate, and PCI-DSS profiles.

```bash
./core/apply-periodic-scan.sh
./core/apply-periodic-scan.sh --platform rhcos   # Node profiles only
./core/apply-periodic-scan.sh --no-pvc --dry-run
```

**create-scan.sh** — Creates an on-demand scan using the built-in `default` ScanSetting. By default it scans all profiles (E8, CIS, Moderate, PCI-DSS for OCP and RHCOS).

```bash
./core/create-scan.sh                       # All profiles
./core/create-scan.sh --platform ocp        # ocp4-* profiles only
./core/create-scan.sh --platform rhcos      # rhcos4-* profiles only
./core/create-scan.sh -p ocp4-cis           # A single profile
./core/create-scan.sh --dry-run
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
python3 core/combine-machineconfigs-by-path.py --src-dir complianceremediations --out-dir complianceremediations --no-move
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

**export-compliance-data.sh** — Exports ComplianceCheckResults from the cluster to `docs/_data/ocp-X_Y.json` for the dashboard.

```bash
./core/export-compliance-data.sh 5.0
make export-compliance OCP_VERSION=5.0
```

**filter-machineconfig-flags.py** — Builds a focused MachineConfig by selecting named flags from a combined file.

```bash
python3 core/filter-machineconfig-flags.py -i input.yaml -o output.yaml -f PermitRootLogin PasswordAuthentication
make filter-machineconfigs INPUT=input.yaml OUTPUT=output.yaml FLAGS="PermitRootLogin PasswordAuthentication"
```

**add-summaries.py** — Adds pattern-based remediation summaries to a scan export JSON.

```bash
python3 core/add-summaries.py docs/_data/ocp-5_0.json
```

**summarize-remediations.py** — Adds Claude-generated summaries (cached; works offline with `--offline`).

```bash
python3 core/summarize-remediations.py docs/_data/ocp-5_0.json --offline
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

**verify-images.sh** — Checks that operator, content, catalog, and mirror images are pullable.

```bash
./utilities/verify-images.sh
make verify-images
```

**mirror-compliance-images.sh** — Mirrors (or builds) compliance-operator images to `IMAGE_REGISTRY`.

```bash
./utilities/mirror-compliance-images.sh v1.9.0
make mirror-images CO_REF=v1.9.0
```

**verify-mirror-architectures.sh** — Confirms mirrored images include amd64 and arm64.

```bash
./utilities/verify-mirror-architectures.sh
```

**build-k8scontent.sh** — Builds the ComplianceAsCode k8scontent image from source and pushes it to the mirror registry.

```bash
./utilities/build-k8scontent.sh           # from master
./utilities/build-k8scontent.sh v0.1.81   # from a git ref
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

## Analysis and Validation (`scripts/`)

**preflight-check.sh** — Verifies CLI tools, Python packages, and cluster connectivity.

```bash
./scripts/preflight-check.sh
make preflight
```

**test-compliance.sh** — Runs the same install/scan assertions used in CI against a connected cluster.

```bash
./scripts/test-compliance.sh
make test-compliance
```

**validate-machineconfig.sh** — Validates MachineConfig YAML before apply.

```bash
./scripts/validate-machineconfig.sh -d complianceremediations
make validate-machineconfigs
```

**detect-mc-conflicts.sh** — Reports file-path, sysctl, and kernel-arg conflicts between MachineConfigs.

```bash
./scripts/detect-mc-conflicts.sh -t docs/_data/tracking.json complianceremediations/
make detect-conflicts
```

**diff-scans.py** — Compares two scan export JSON files (status changes, new/removed checks).

```bash
python3 scripts/diff-scans.py old.json new.json
make diff-scans OLD=old.json NEW=new.json
```

**suggest-groups.py** — Suggests remediation groups for ungrouped checks.

```bash
python3 scripts/suggest-groups.py docs/_data/ocp-5_0.json
make suggest-groups SCAN=docs/_data/ocp-5_0.json
```

**validate-dashboard-data.py** — Validates `docs/_data/` JSON (tracking, scan exports, group-matrix, upstream PRs).

```bash
python3 scripts/validate-dashboard-data.py docs/_data/
make validate-dashboard-data
```

**add-version.py** — Scaffolds dashboard pages and tracking files for a new OCP version.

```bash
python3 scripts/add-version.py --source 5.0 --target 5.1
make add-version OCP_VERSION=5.1 SOURCE_VERSION=5.0
```

**generate-group-matrix.py** — Builds `docs/_data/group-matrix.json` for the Hardened dashboard page from scan data and the latest tracking file.

```bash
python3 scripts/generate-group-matrix.py
```

**backfill-scan-profiles.py** — Fills per-profile pass/fail/manual counts in `scan-history.json`.

```bash
python3 scripts/backfill-scan-profiles.py
```

**rhcos-static-scan.sh** — Runs an offline OSCAP scan against an RHCOS rootfs.

```bash
./scripts/rhcos-static-scan.sh 4.21
make rhcos-static-scan OCP_VERSION=4.21
```

**parse-oscap-results.py** — Parses OSCAP XCCDF results XML (used when refreshing RHCOS baselines).

```bash
python3 scripts/parse-oscap-results.py /tmp/rhcos-scan-results/results-e8.xml --failing-only --format text
```

**verify-all-groups.sh** — Applies tracked remediation groups, re-scans, and reports FAIL→PASS flips.

```bash
./scripts/verify-all-groups.sh --dry-run
./scripts/verify-all-groups.sh --groups H1,H2 --batch-size 2
```

**update-marketplace-versions.sh** — Refreshes the community-operator-index tag list in `verify-images.sh`.

```bash
./scripts/update-marketplace-versions.sh --dry-run
```
