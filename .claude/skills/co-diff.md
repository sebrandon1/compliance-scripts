# Compare Compliance Scan Results

Compare compliance check results between two scan exports, or between a saved export and a live cluster.

## Inputs

The user provides one of:
- **Two JSON file paths** — compare exported scan data files (e.g., `docs/_data/ocp-4_22.json` vs `docs/_data/ocp-5_0.json`)
- **One JSON file path + kubeconfig** — compare a saved export against live cluster results
- **Kubeconfig + OCP version** — compare live cluster results against tracking.json group expectations

If the user just says "diff" or "compare", ask which mode they want.

## Workflow

### Mode 1: File vs File

Run the existing diff tool directly:

```bash
python3 scripts/diff-scans.py <old.json> <new.json>
```

This produces a human-readable report with:
- Summary delta table (total, passing, failing, manual)
- Regressions (PASS -> FAIL) separated by OCP platform vs RHCOS node
- Fixes (FAIL -> PASS)
- New and removed checks
- Other status changes

Exit code 1 means regressions were found.

### Mode 2: File vs Cluster

1. Export live cluster data to a temp file:

```bash
KUBECONFIG=<path> ./core/export-compliance-data.sh <version>
```

This creates `docs/_data/ocp-<version>.json`. If the user doesn't want to overwrite existing data, export to a temp path instead:

```bash
TMPFILE=$(mktemp /tmp/compliance-export-XXXXXX.json)
KUBECONFIG=<path> OCP_VERSION=<version> ./core/export-compliance-data.sh <version>
# Then move the output to the temp location
```

2. Run the diff:

```bash
python3 scripts/diff-scans.py <baseline.json> <live-export.json>
```

### Mode 3: Cluster vs Tracking

Compare live cluster FAIL results against `docs/_data/tracking.json` to identify which hardening groups would remediate which failures.

1. Get all failing checks from the cluster:

```bash
KUBECONFIG=<path> oc get compliancecheckresult -n openshift-compliance -o json | \
  python3 -c "import json,sys; data=json.load(sys.stdin); [print(i['metadata']['name']) for i in data['items'] if i['status']=='FAIL']"
```

2. Read `docs/_data/tracking.json` and map each failing check to its remediation group using the `remediations` mapping.

3. Report a table:

| Group | Title | Status | Failing Checks | Count |
|-------|-------|--------|---------------|-------|
| M2 | Sysctl Network | verified | sysctl_net_... | 12 |
| H1 | Crypto Policy | verified | crypto-policy... | 2 |
| (ungrouped) | — | — | check-name... | N |

This shows which groups to apply to fix the most failures, and highlights any failing checks that aren't mapped to any group.

## Arguments

- `--json` — pass through to `diff-scans.py` for machine-readable JSON output
- `--platform ocp|rhcos` — filter diff results to one platform only

## Important Notes

- The diff tool (`scripts/diff-scans.py`) already exists with full test coverage — always use it rather than reimplementing
- Regressions (PASS -> FAIL) are the most important output — highlight them prominently
- When comparing across major versions (e.g., 4.22 vs 5.0), expect content image changes to add/remove checks — these are separate from regressions
- For file-vs-cluster mode, the OCP version is needed to name the export file — get it from `oc get clusterversion` if not provided
- Available baseline files are in `docs/_data/` — list them if the user doesn't specify which to compare against
