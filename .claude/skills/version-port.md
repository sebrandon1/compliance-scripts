# Port Groupings to New OCP Version

Port the entire compliance grouping system to a new OCP version (e.g., 4.22 -> 4.23).

## Inputs

The user provides:
- Source version (e.g., 4.22)
- Target version (e.g., 4.23)
- Target cluster kubeconfig (optional — needed for scan export)

## Workflow

### Step 1: Create Version Pages

```bash
cp -r docs/versions/<source>/ docs/versions/<target>/
cp docs/versions/<source>.md docs/versions/<target>.md
```

Update all references in the copied files:
- Version strings: `<source>` -> `<target>`
- Compare links: `compliance/<source>/` -> `compliance/<target>/`
- Navigation links: `<source>.html` -> `<target>.html`

### Step 2: Create telco-reference Branches

Sync fork, then for each group with a compare link:
1. Create `compliance/<target>/<slug>` branch from main
2. Copy content from the source version branch
3. Commit (1 commit), push

### Step 3: Run Scans (if cluster available)

Use the `/scan-export` skill with the target version and cluster kubeconfig.

### Step 4: Compare Remediations

Diff new remediations against source version:
- New checks? Changed results? Identical YAMLs?

### Step 5: Lint, Commit, and Push

Run `make lint`, commit all new version pages and scan data, push to main.

## Important Notes

- Always scan all 4 profiles (E8, CIS, Moderate, PCI-DSS) for consistency
- Remediation YAMLs are typically identical across minor versions
- SCAP content updates (via `latest` tag) can change results between scans
- The version landing page needs only frontmatter: `layout: version`, `title`, `version`
