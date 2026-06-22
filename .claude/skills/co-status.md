# Compliance Operator Status Dashboard

Show a quick overview of compliance operator state on a connected OCP cluster.

## Inputs

The user provides:
- Cluster kubeconfig path (ask user if not obvious from context)

## Workflow

### Step 1: Cluster Info

Gather cluster identity in parallel:

```bash
KUBECONFIG=<path> oc get clusterversion -o jsonpath='{.items[0].status.desired.version}'
KUBECONFIG=<path> oc get nodes -o wide
```

Report:
- OCP version
- RHCOS version (from OS-IMAGE column of first node)
- Node count and roles

### Step 2: Operator Health

```bash
KUBECONFIG=<path> oc get pods -n openshift-compliance -o wide
```

Report pod status in a compact table. Flag any pods not in Running/Completed state.

### Step 3: ProfileBundle Status

```bash
KUBECONFIG=<path> oc get profilebundle -n openshift-compliance
```

Report each bundle's status (VALID/PENDING/ERROR). If any are not VALID, warn — scans cannot run until bundles are ready.

### Step 4: Content Image

```bash
KUBECONFIG=<path> oc get profilebundle -n openshift-compliance -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.contentImage}{"\n"}{end}'
```

Show which content image each ProfileBundle is using. Note if it's a pinned digest vs floating tag.

### Step 5: Scan Status

```bash
KUBECONFIG=<path> oc get compliancesuite -n openshift-compliance
```

Report each suite's phase (DONE/RUNNING/PENDING) and result (COMPLIANT/NON-COMPLIANT). If any suites are RUNNING, show how long they've been running.

### Step 6: Check Result Summary

```bash
KUBECONFIG=<path> oc get compliancecheckresult -n openshift-compliance -o json
```

Process the JSON to produce a summary table:

| | PASS | FAIL | MANUAL | Total |
|---|---|---|---|---|
| **OCP (platform)** | N | N | N | N |
| **RHCOS (node)** | N | N | N | N |
| **Total** | N | N | N | N |

Classify by prefix: `ocp4-*` = OCP platform, `rhcos4-*` = RHCOS node.

Also show coverage percentage: `PASS / (PASS + FAIL) * 100`.

### Step 7: Final Report

Combine all sections into a single compact report. Use tables, not verbose prose. Flag any issues that need attention (unhealthy pods, pending bundles, running scans, regressions from expected counts).

## Important Notes

- All `oc` commands must include `KUBECONFIG=<path>` — never assume the default context is correct
- The compliance namespace is always `openshift-compliance`
- If no ComplianceCheckResults exist, report that scans haven't been run yet (don't error)
- If the operator isn't installed (no pods in namespace), say so clearly and suggest using `/co-scan` to install and run
