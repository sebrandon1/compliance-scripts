# Update Group Status

Update a remediation group's status across all tracking surfaces when a PR merges or status changes.

## Inputs

The user provides:
- Group ID (e.g., M1)
- New status: `in_progress`, `complete`, `on_hold`, or `pending`
- OCP version (e.g., 4.22) — defaults to latest version in `docs/versions/`

## Workflow

### Step 1: Verify Current State

Read `docs/_data/tracking.json` for the group's current status, Jira key, and PR number. Confirm the transition makes sense (e.g., don't mark complete if PR isn't merged).

If marking `complete`, verify the PR is actually merged:
```bash
gh pr view <PR_NUMBER> --repo openshift-kni/telco-reference --json state
```

### Step 2: Update Files and Jira (parallel)

**File edits:**
1. Update `tracking.json`: set `status` field
2. Update `docs/versions/<VERSION>/groups/index.md`: change status emoji
   - `pending` → `🟡 Pending`
   - `in_progress` → `🔵 In Progress`
   - `on_hold` → `⚪ On Hold`
   - `complete` → `🟢 Complete`
3. Update `docs/versions/<VERSION>/remediations.md` similarly (uses HTML `<span class="status-pill ...">`)
4. Run `make lint`

**Jira updates (parallel):**
If the group has a Jira key:
1. Get available transitions via `jira_get_transitions` (do NOT hardcode transition IDs)
2. Transition to the matching status
3. If completing, add comment: "Remediation merged via PR #XXX"

### Step 3: Commit and Push

Commit tracking/dashboard changes to compliance-scripts main.
