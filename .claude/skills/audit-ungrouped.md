# Audit Ungrouped Remediations

Find compliance remediations that aren't mapped to any group and suggest new groups.

## Inputs

None required. Operates on the local `complianceremediations/` directory and `docs/_data/tracking.json`. If `complianceremediations/` is empty, instruct the user to run `/scan-export` first.

## Workflow

### Step 1: Load Current Groups

Read `docs/_data/tracking.json` — both the `groups` section (for group metadata) and the `remediations` section (for check-to-group mappings).

### Step 2: List All Collected Remediations

Scan all YAML files (excluding `*-combo.yaml`):
- `complianceremediations/*.yaml`
- `complianceremediations/high/*.yaml`
- `complianceremediations/medium/*.yaml`
- `complianceremediations/low/*.yaml`

Extract unique check names by stripping profile and role prefixes:
- `rhcos4-e8-master-<check>.yaml` → `<check>`
- `rhcos4-moderate-worker-<check>.yaml` → `<check>`
- `ocp4-cis-<check>.yaml` → `<check>`

Dedup across profiles — same check from E8 and Moderate counts once.

### Step 3: Identify Ungrouped

Cross-reference check names against `tracking.json` remediations. Report grouped vs ungrouped counts.

### Step 4: Suggest New Groups

Categorize ungrouped checks by type prefix and suggest group IDs:

| Suggested Group | Title | Checks | Profile |
|----------------|-------|--------|---------|
| M31 | ... | 5 | rhcos4-moderate |

### Step 5: Offer Next Steps

Ask the user if they want to create any of the suggested groups using `/new-group`.

## Important Notes

- `complianceremediations/medium/` only has E8 checks; Moderate checks are in the root dir
- CIS/PCI-DSS checks often duplicate E8/Moderate — only group unique remediations
- OCP-level checks (ocp4-*) are CRDs, not MachineConfigs
