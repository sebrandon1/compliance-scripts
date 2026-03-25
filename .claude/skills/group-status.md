# Update Group Status

Update a remediation group's status across all tracking surfaces when a PR merges or status changes.

## Inputs

The user provides:
- Group ID (e.g., M1)
- New status: `in_progress`, `complete`, `on_hold`, or `pending`

## Workflow

### Step 1: Update tracking.json

Edit `docs/_data/tracking.json`:
- Set the group's `status` field
- If completing: note the PR merge date

### Step 2: Update Dashboard Pages

Edit `docs/versions/4.22/groups/index.md`:
- Change the status emoji and text for the group's row
- Status mapping:
  - `pending` → `🟡 Pending`
  - `in_progress` → `🔵 In Progress`
  - `on_hold` → `⚪ On Hold`
  - `complete` → `🟢 Complete`

Update `docs/versions/4.22/remediations.md` similarly if the group appears there.

### Step 3: Update Jira

If the group has a Jira key in tracking.json:
- Get available transitions: `jira_get_transitions`
- Transition to matching status:
  - `in_progress` → transition ID 21
  - `complete` → transition ID 51 (Closed) with resolution Fixed
- Add comment if completing: "Remediation merged via PR #XXX"

### Step 4: Commit and Push

Commit tracking/dashboard changes to compliance-scripts main.

## Important Notes

- When marking complete, verify the PR is actually merged first
- Don't close Jiras without confirming the PR merged
- The remediations.md file uses HTML table format, not markdown tables
