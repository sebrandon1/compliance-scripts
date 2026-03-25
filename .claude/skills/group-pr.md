# Create PR and Jira for a Remediation Group

Create a Jira story, telco-reference PR, and link everything together for a remediation group.

## Inputs

The user provides:
- Group ID (e.g., M13)
- Epic key (e.g., CNF-22573)
- OCP version target (e.g., 4.23)

## Workflow

### Step 1: Get Group Info

Read `docs/_data/tracking.json` for the group's title, severity, and compare branch slug.
Read `docs/versions/<VERSION>/groups/<GROUP_ID>.md` for checks and descriptions.
Verify the telco-reference branch exists before proceeding.

### Step 2: Create Jira Story

Create in project CNF using mcp-atlassian `jira_create_issue`:
- **Type**: Story
- **Summary**: `RAN Hardening - <Title> (<Group ID>)`
- **Assignee**: bpalm@redhat.com
- **Labels**: compliance, hardening, medium-severity, telco-ran
- **Epic link**: `customfield_10014: <EPIC_KEY>`
- **Priority**: Major
- **Description**: Jira wiki format with:
  - Settings table: `|| Setting || Value || Description ||` then `| val | val | val |`
  - Remediation group link: `[Title|https://sebrandon1.github.io/...]`
  - Compare link
  - Related epic link: `[EPIC_KEY|https://redhat.atlassian.net/browse/EPIC_KEY]`

### Step 3: Create telco-reference PR

PR title: `CNF-XXXXX: RAN Hardening (<VERSION>) - <Title> (<GROUP_ID>)`

PR body:
- Summary (1-3 bullets)
- Remediation Group link
- Jira link + Epic link
- Test plan with checkboxes

No "Generated with Claude Code" footer.

### Step 4: Update Tracking (file edits and Jira calls can be parallel)

**File edits:**
1. Update `tracking.json`: set `jira`, `pr`, `status: in_progress`
2. Update `docs/versions/<VERSION>/groups/index.md`: add Jira link, PR link, change status to In Progress
3. Run `make lint`

**Jira updates (parallel with file edits):**
1. Add comment to Jira: `PR created: <URL>`
2. Get available transitions via `jira_get_transitions`, then transition to In Progress

### Step 5: Commit and Push

Commit tracking/dashboard changes to compliance-scripts main.
