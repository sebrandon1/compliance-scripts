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

### Step 4: Auto-Suggest Groups

Run the auto-grouping script to suggest which existing group each ungrouped check belongs to:

```bash
python3 scripts/suggest-groups.py docs/_data/ocp-<VERSION>.json
```

Or for version-specific tracking:

```bash
python3 scripts/suggest-groups.py --tracking docs/_data/tracking-5_0.json docs/_data/ocp-5_0.json
```

The script outputs suggestions ranked by confidence (high >0.9, medium 0.5-0.9, unmatched). Review the suggestions and note any that need manual override.

### Step 5: Offer Next Steps

For checks with high/medium confidence suggestions — ask the user if they want to add these mappings to tracking.json.

For unmatched checks — ask if the user wants to create new groups using `/new-group`.

## Important Notes

- `complianceremediations/medium/` only has E8 checks; Moderate checks are in the root dir
- CIS/PCI-DSS checks often duplicate E8/Moderate — only group unique remediations
- OCP-level checks (ocp4-*) are CRDs, not MachineConfigs
