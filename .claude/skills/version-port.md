# Port Groupings to New OCP Version

Port the entire compliance grouping system to a new OCP version (e.g., 4.22 -> 5.0).

## Inputs

The user provides:
- Source version (e.g., 4.22)
- Target version (e.g., 5.0)
- Target cluster kubeconfig (optional — needed for scan export)

## Workflow

### Step 1: Create Version Pages

```bash
cp -r docs/versions/<source>/ docs/versions/<target>/
cp docs/versions/<source>.md docs/versions/<target>.md
```

Update all references in the copied files:
- `version: "<source>"` -> `version: "<target>"` in frontmatter
- Version strings in titles and text: `<source>` -> `<target>`
- Compare links: `compliance/<source>/` -> `compliance/<target>/`
- Navigation links: `<source>.html` -> `<target>.html`
- RHCOS version references (e.g., `RHCOS 9.8` -> `RHCOS 10.2` for 5.0)

Use python for bulk replacement — macOS `sed -i ''` has quirks with multiple `-e` flags:

```python
import os
replacements = [
    ('version: "<source>"', 'version: "<target>"'),
    ('OCP <source>', 'OCP <target>'),
    # ... etc
]
for root, dirs, files in os.walk('docs/versions/<target>'):
    for fname in files:
        if fname.endswith('.md'):
            # read, replace, write
```

### Step 2: Create Version-Specific Tracking Data

Create `docs/_data/tracking-<target_slug>.json` from the shared tracking.json:

```python
import json
with open('docs/_data/tracking.json') as f:
    data = json.load(f)

# Reset version-specific fields
for gid, g in data['groups'].items():
    g['status'] = 'pending'
    g['status_note'] = None
    g['jira'] = None
    g['jira_status'] = None
    g['pr'] = None
    g['pr_state'] = None
    g['last_sync'] = None
    if g.get('compare'):
        g['compare'] = g['compare'].replace('compliance/<source>/', 'compliance/<target>/')

# Reset meta
data['meta']['epic'] = None
data['meta']['last_sync'] = None
data['meta']['last_upstream_audit'] = None
data['meta']['upstream_audit_note'] = None

with open('docs/_data/tracking-<target_slug>.json', 'w') as f:
    json.dump(data, f, indent=2)
```

The layouts automatically resolve `tracking-<version_slug>.json` via `_includes/resolve-tracking.html`, falling back to the shared `tracking.json` if no version-specific file exists.

### Step 3: Run Scans (if cluster available)

Use the `/co-scan` skill with the target version and cluster kubeconfig. This will:
1. Install the compliance operator if needed
2. Run all 4 profiles (E8, CIS, Moderate, PCI-DSS)
3. Wait for completion
4. Export to `docs/_data/ocp-<target_slug>.json`

### Step 4: Create telco-reference Branches

Sync fork, then for each group with a compare link:
1. Create `compliance/<target>/<slug>` branch from main
2. Copy content from the source version branch
3. Commit (1 commit), push

### Step 5: Compare Remediations

Use the `/co-diff` skill to compare new scan results against the source version:

```bash
python3 scripts/diff-scans.py docs/_data/ocp-<source_slug>.json docs/_data/ocp-<target_slug>.json
```

Review regressions — checks that were PASS on the source version but FAIL on the target may indicate RHCOS version changes or content image differences.

### Step 6: Lint, Commit, and Push

Run `make lint`, commit all new version pages, tracking data, and scan data.

## How Version-Aware Tracking Works

Each version can have its own tracking file (`tracking-<version_slug>.json`) in `docs/_data/`. The shared include `_includes/resolve-tracking.html` resolves the correct file:

```liquid
{% assign version_slug = page.version | replace: ".", "_" %}
{% assign tracking_file = "tracking-" | append: version_slug %}
{% assign tracking = site.data[tracking_file] | default: site.data.tracking %}
```

All layouts, includes, and version-specific pages use this include. When no version-specific tracking file exists, the shared `tracking.json` is used as fallback.

**Important**: All version-specific `.md` pages (`remediations.md`, `groups/index.md`) must have `version:` in their front matter for the tracking resolution to work.

## Important Notes

- Always scan all 4 profiles (E8, CIS, Moderate, PCI-DSS) for consistency
- Remediation YAMLs are typically identical across minor versions but may change across major versions (e.g., 4.x -> 5.x with RHCOS 10)
- SCAP content updates (via `latest` tag) can change results between scans
- The version landing page needs only frontmatter: `layout: version`, `title`, `version`
- "pass-vanilla" statuses from one RHCOS version need re-evaluation on newer versions — don't carry them forward without verification
