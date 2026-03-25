# Port Groupings to New OCP Version

Port the entire compliance grouping system to a new OCP version (e.g., 4.22 → 4.23).

## Inputs

The user provides:
- Source version (e.g., 4.22)
- Target version (e.g., 4.23)
- Target cluster kubeconfig (optional — needed for scan export)

## Workflow

### Step 1: Create Version Pages

Copy the source version's dashboard pages to the target:

```bash
cp -r docs/versions/<source>/ docs/versions/<target>/
cp docs/versions/<source>.md docs/versions/<target>.md
```

Update all references:
- Version strings: `4.22` → `4.23`
- Compare links: `compliance/4.22/` → `compliance/4.23/`
- Navigation links: `4.22.html` → `4.23.html`

### Step 2: Create telco-reference Branches

For each group with a compare link, create a `compliance/<target>/` branch in telco-reference:

1. Sync fork main to upstream
2. For each group slug:
   - Create branch from main
   - Copy content from the source version branch
   - Update any version references in YAML comments
   - Commit (1 commit), push

### Step 3: Run Scans on Target Version (if cluster available)

Use the `/scan-export` skill:
1. Install compliance operator
2. Run all 4 profile scans
3. Export to `docs/_data/ocp-<target>.json`

### Step 4: Compare Remediations

Diff the new scan's remediations against the source version:
- Are there new checks?
- Did any checks change from FAIL to PASS or vice versa?
- Are the remediation YAMLs identical?

### Step 5: Update Dashboard

If scan data was exported, verify the version card shows on the main dashboard page. Update group pages with any version-specific findings.

### Step 6: Commit and Push

Commit all new version pages and scan data.

## Important Notes

- Always scan all 4 profiles (E8, CIS, Moderate, PCI-DSS) for consistency
- Remediation YAMLs are typically identical across minor versions (verified 4.21 vs 4.22)
- H3 (sshd-disable-empty-passwords) changed from PASS to FAIL between Jan and Mar 2026 scans — SCAP content updates can change results
- The version landing page (`docs/versions/<ver>.md`) needs only frontmatter: layout, title, version
