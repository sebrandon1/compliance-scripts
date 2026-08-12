# Sync Upstream PRs

Refresh all upstream PR data displayed on the hardened dashboard. Updates two independent data sources:

1. **Compliance-Operator PRs** (`docs/_data/upstream-prs.json`) — all PRs by sebrandon1 to `ComplianceAsCode/compliance-operator`
2. **Remediation PRs** (in `docs/_data/tracking-*.json`) — PRs in group `upstream[].pr_history[]` entries across `ComplianceAsCode/content`, `openshift/os`, and `coreos/rhel-coreos-config`

## Usage

- `/sync-upstream-prs` — update both data sources
- `/sync-upstream-prs operator` — update only compliance-operator PRs
- `/sync-upstream-prs remediation` — update only remediation PRs in tracking files

## Workflow

### Step 1: Sync Compliance-Operator PRs

Fetch the current PR list from GitHub:

```bash
gh pr list --repo ComplianceAsCode/compliance-operator --author sebrandon1 --state all --json number,title,url,state --limit 100
```

Compare against `docs/_data/upstream-prs.json`:
- **New PRs**: add entries (state is lowercased: `OPEN` → `open`, `MERGED` → `merged`, `CLOSED` → `closed`)
- **State changes**: update existing entries (e.g., `open` → `merged`)
- **Title changes**: update titles
- Preserve the existing sort order (newest first by PR number)

Write the updated JSON. Each entry has exactly these fields:
```json
{
  "number": 1203,
  "title": "Replace panics with error returns in production code",
  "url": "https://github.com/ComplianceAsCode/compliance-operator/pull/1203",
  "state": "open"
}
```

Report what changed: new PRs added, state transitions, total counts.

### Step 2: Sync Remediation PRs in Tracking Files

For each tracking file (`docs/_data/tracking-4_22.json`, `tracking-5_0.json`, `tracking.json`, etc.), find all `upstream[].pr_history[]` entries that have a `url` field.

For each filed PR, query its current state:

```bash
gh pr view <URL> --json state
```

Compare the GitHub state (lowercased) against the `state` field in the tracking data. If the state changed (e.g., `open` → `merged`), update the `state` field in the tracking JSON.

The repos to check are:
- `ComplianceAsCode/content`
- `openshift/os`
- `coreos/rhel-coreos-config`

Tracking PR history entry fields (preserve all existing fields, only update `state`):
```json
{
  "repo": "ComplianceAsCode/content",
  "pr": 14602,
  "url": "https://github.com/ComplianceAsCode/content/pull/14602",
  "state": "open",
  "opened": "2026-03-27",
  "outcome": null,
  "reason": "..."
}
```

If a PR was merged, also set `outcome` to `"merged"` if it was previously `null`.

Update ALL tracking files that reference the same PR URL (they share the same upstream data structure).

Report which PRs changed state and in which tracking files.

### Step 3: Validate and Summarize

Run the dashboard validator to make sure nothing broke:

```bash
python3 scripts/validate-dashboard-data.py docs/_data/
```

Print a summary:
- Compliance-operator: X total PRs (Y open, Z merged, W closed)
- Remediation PRs: X total across N groups (Y open, Z merged/closed)
- Any state changes detected this run

Do NOT commit automatically — let the user review and decide.
