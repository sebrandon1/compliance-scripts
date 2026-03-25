# Create PR and Jira for a Remediation Group

Create a Jira story, telco-reference PR, and link everything together for a remediation group.

## Inputs

The user provides:
- Group ID (e.g., M13)
- Epic key (e.g., CNF-22573 for 4.23)
- OCP version target (e.g., 4.23)

## Workflow

### Step 1: Get Group Info

Read `docs/_data/tracking.json` for the group's title, severity, compare branch slug.
Read `docs/versions/4.22/groups/<GROUP_ID>.md` for checks and descriptions.

### Step 2: Create Jira Story

Create in project CNF using mcp-atlassian:
- **Type**: Story
- **Summary**: `RAN Hardening - <Title> (<Group ID>)`
- **Assignee**: bpalm@redhat.com
- **Labels**: compliance, hardening, medium-severity, telco-ran
- **Epic link**: `customfield_10014: <EPIC_KEY>`
- **Priority**: Major
- **Description**: Jira wiki format with settings table, remediation group link, compare link, related epic link

Match the format of CNF-21212 / CNF-22620.

### Step 3: Create telco-reference PR

```bash
gh pr create --repo openshift-kni/telco-reference \
  --head sebrandon1:compliance/4.22/<slug> \
  --base main \
  --title "CNF-XXXXX: RAN Hardening (<VERSION>) - <Title> (<GROUP_ID>)" \
  --body "..."
```

PR body format:
- Summary (1-3 bullets)
- Remediation Group link
- Jira link + Epic link
- Test plan with checkboxes

### Step 4: Update Tracking

1. Update `tracking.json`: set `jira`, `pr`, `status: in_progress`
2. Update `docs/versions/4.22/groups/index.md`: add Jira link, PR link, change status to In Progress
3. Add comment to Jira: `PR created: <URL>`
4. Transition Jira to In Progress (transition ID 21)

### Step 5: Commit and Push

Commit tracking/dashboard changes to compliance-scripts main.

## Important Notes

- PR title pattern: `CNF-XXXXX: RAN Hardening (4.XX) - Description (Group)`
- No "Generated with Claude Code" footer in PR descriptions
- Jira description uses wiki markup (not markdown): `||header||`, `|cell|`, `*bold*`, `[text|url]`
- Always comment PR URL on Jira after creation
