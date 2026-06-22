# Run Compliance Scans

Install the compliance operator (if needed), run scans, wait for completion, and export results.

## Inputs

The user provides:
- Cluster kubeconfig path (ask user if not obvious from context)
- OCP version (e.g., 4.22, 5.0) — used for export filename. Auto-detect from `oc get clusterversion` if not provided.
- Platform filter: `all` (default), `ocp`, `rhcos`
- Compliance operator version (default: use whatever is installed; `v1.7.0` for fresh installs)

## Workflow

### Step 1: Preflight

Check cluster connectivity and operator state:

```bash
KUBECONFIG=<path> oc get clusterversion
KUBECONFIG=<path> oc get pods -n openshift-compliance
```

If no pods in `openshift-compliance`, the operator isn't installed — ask the user if they want to install it, then:

```bash
KUBECONFIG=<path> CO_REF=<version> make install-compliance-operator
```

Wait for pods to be Ready and ProfileBundles to be VALID before proceeding.

### Step 2: Check Existing Scans

```bash
KUBECONFIG=<path> oc get compliancesuite -n openshift-compliance
```

- If suites exist and are **DONE**: ask if user wants to delete and re-scan, or just export existing results
- If suites exist and are **RUNNING**: monitor them instead of creating new ones
- If no suites exist: proceed to create scans

To delete existing scans for a fresh run:

```bash
KUBECONFIG=<path> oc delete compliancesuite --all -n openshift-compliance
KUBECONFIG=<path> oc delete scansettingbinding --all -n openshift-compliance
```

### Step 3: Create Scans

```bash
KUBECONFIG=<path> make create-scan
```

Or with platform filter:

```bash
KUBECONFIG=<path> ./core/create-scan.sh --platform <ocp|rhcos>
```

**Standard**: Always scan all 4 profiles (E8, CIS, Moderate, PCI-DSS) for consistency across versions.

### Step 4: Monitor Progress

Poll every 30 seconds until all suites show DONE:

```bash
KUBECONFIG=<path> oc get compliancesuite -n openshift-compliance
```

For detailed progress, use:

```bash
KUBECONFIG=<path> ./utilities/monitor-inprogress-scans.sh
```

**Timeout after 30 minutes** — if stuck, check:
- Scan pod status: `oc get pods -n openshift-compliance | grep -i scan`
- Operator logs: `oc logs deployment/compliance-operator -n openshift-compliance --tail=50`
- Scanner pod logs for the stuck scan

### Step 5: Export Results

```bash
KUBECONFIG=<path> make export-compliance OCP_VERSION=<version>
```

This creates `docs/_data/ocp-<version_slug>.json`.

### Step 6: Auto-Diff (Optional)

If a previous version's export exists in `docs/_data/`, automatically run a diff:

```bash
python3 scripts/diff-scans.py docs/_data/ocp-<prev_version>.json docs/_data/ocp-<new_version>.json
```

Report any regressions prominently.

### Step 7: Summary

Print a compact summary:
- OCP version and RHCOS version
- Total checks: PASS / FAIL / MANUAL
- Coverage percentage
- Number of regressions from previous version (if diff was run)
- Path to exported JSON file

## Important Notes

- Scans take 5-15 minutes depending on cluster size and number of nodes
- On SNO/CRC: the scripts auto-detect single-node and use worker role only
- Always scan all 4 profiles for consistency — don't skip profiles even if only interested in one
- The compliance namespace is always `openshift-compliance`
- If ProfileBundles are stuck in PENDING, check for ImagePullBackOff on profile parser pods and storage issues
- Pull secret may need updating: `misc/replace-pull-secret-credentials.sh --pull-secret <path>`
