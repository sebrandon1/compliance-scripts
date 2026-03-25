# Scan and Export Compliance Data

Install the compliance operator, run all scans, and export data to the dashboard.

## Inputs

The user provides:
- OCP version (e.g., 4.22, 4.23)
- Cluster kubeconfig path (ask user if not obvious from context)
- Compliance operator version (default: v1.7.0)

## Workflow

### Step 1: Preflight

1. Verify cluster connectivity: `oc get clusterversion`
2. Ensure pull secret is configured. If operator images fail to pull, run:
   `misc/replace-pull-secret-credentials.sh --pull-secret <path>`

### Step 2: Install and Scan

```bash
KUBECONFIG=<path> CO_REF=<version> make install-compliance-operator
KUBECONFIG=<path> make apply-periodic-scan
```

This installs the operator and runs all 4 profiles: E8, CIS, Moderate, PCI-DSS.
**Standard**: Always scan all 4 profiles for consistency across versions.

### Step 3: Wait for Completion

Poll ComplianceSuites until all show DONE. **Timeout after 30 minutes** — if stuck, check operator logs and scan pod status.

### Step 4: Collect and Export

```bash
KUBECONFIG=<path> make collect-complianceremediations
KUBECONFIG=<path> make export-compliance OCP_VERSION=<version>
```

Creates `docs/_data/ocp-<version>.json`.

### Step 5: Create Version Pages (if new version)

If `docs/versions/<version>/` doesn't exist, use the `/version-port` skill to create it from the previous version.

### Step 6: Lint, Commit, and Push

Run `make lint`, commit exported data and any new version pages, push to main.

## Important Notes

- On SNO/CRC: `apply-periodic-scan.sh` auto-detects and uses worker role only
- scannerType CRD patch is applied automatically by the install script
