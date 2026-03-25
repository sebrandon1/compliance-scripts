# Audit Ungrouped Remediations

Find compliance remediations that aren't mapped to any group and suggest new groups.

## Workflow

### Step 1: Load Current Groups

Read `docs/_data/tracking.json` to get all grouped check patterns from the `remediations` section.

### Step 2: List All Collected Remediations

Scan `complianceremediations/` for all YAML files (excluding combo files):
- `complianceremediations/*.yaml`
- `complianceremediations/high/*.yaml`
- `complianceremediations/medium/*.yaml`
- `complianceremediations/low/*.yaml`

Extract unique check names by stripping profile and role prefixes:
- `rhcos4-e8-master-<check>.yaml` → `<check>`
- `rhcos4-moderate-worker-<check>.yaml` → `<check>`
- `ocp4-cis-<check>.yaml` → `<check>`

### Step 3: Identify Ungrouped

For each unique check name, check if it matches any pattern in `tracking.json` remediations. Report:

```
=== Grouped (X checks) ===
- configure-crypto-policy → H1
- no-empty-passwords → H2
...

=== Ungrouped (Y checks) ===
- some-new-check (rhcos4-moderate, MEDIUM)
- another-check (ocp4-cis, HIGH)
...
```

### Step 4: Suggest New Groups

Categorize ungrouped checks by type and suggest group names:
- Audit rules → audit group
- Sysctl → sysctl group
- Kernel modules → module group
- SSHD → SSHD group
- etc.

### Step 5: Report

Present a table:

| Suggested Group | Title | Checks | Profile |
|----------------|-------|--------|---------|
| M31 | ... | 5 | rhcos4-moderate |

## Important Notes

- Some checks overlap across profiles (same remediation, different profile prefix) — dedup by check suffix
- CIS/PCI-DSS checks often duplicate E8/Moderate checks — only group unique remediations
- `complianceremediations/medium/` only has E8 checks; Moderate checks are in root dir
- OCP-level checks (ocp4-*) are CRDs, not MachineConfigs
