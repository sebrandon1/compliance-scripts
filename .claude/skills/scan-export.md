# Scan and Export Compliance Data

Install the compliance operator, run all scans, and export data to the dashboard.

## Inputs

The user provides:
- OCP version (e.g., 4.22, 4.23)
- Cluster kubeconfig path (default: `~/Downloads/cnfdt16-kubeconfig`)
- Compliance operator version (default: v1.7.0)

## Workflow

### Step 1: Install Compliance Operator

```bash
KUBECONFIG=<path> CO_REF=<version> make install-compliance-operator
```

Wait for ProfileBundles VALID.

### Step 2: Deploy Scans

```bash
KUBECONFIG=<path> make apply-periodic-scan
```

This runs all 4 profiles: E8, CIS, Moderate, PCI-DSS.
**Standard**: Always scan all 4 profiles for consistency across versions.

### Step 3: Wait for Completion

Poll ComplianceSuites until all show DONE:

```bash
oc get compliancesuite -n openshift-compliance
```

Typical time: 5-15 minutes on multi-node, longer on SNO/CRC.

### Step 4: Collect Remediations

```bash
KUBECONFIG=<path> make collect-complianceremediations
```

### Step 5: Export Dashboard Data

```bash
KUBECONFIG=<path> make export-compliance OCP_VERSION=<version>
```

Creates `docs/_data/ocp-<version>.json`.

### Step 6: Create Version Pages (if new version)

If `docs/versions/<version>/` doesn't exist:
1. Copy from previous version directory
2. Update all version references
3. Update compare links to point to new `compliance/<version>/` branches

### Step 7: Commit and Push

Commit exported data and any new version pages.

## Important Notes

- On SNO/CRC: `apply-periodic-scan.sh` auto-detects and uses worker role only
- scannerType CRD patch is required for v1.7.0 operator
- Pull secret must be configured before operator install (`misc/replace-pull-secret-credentials.sh`)
- v1.8.2 catalog image tag doesn't exist on ghcr.io — use v1.7.0
