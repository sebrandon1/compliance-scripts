---
name: sync-tracking
description: Sync remediation tracking data from Jira and GitHub
---

# Sync Tracking Data

Synchronize the remediation tracking website with current Jira and GitHub status.

## Overview

This skill fetches the latest status from Jira issues and GitHub PRs linked to remediation groups, then updates the local `tracking.json` file with the current state.

## Steps

### 1. Read Current Tracking Data

Read `docs/_data/tracking.json` to get the list of Jira issues and PRs for each group.

### 2. Fetch Jira Status

For each group with a `jira` field, use the `mcp__mcp-atlassian__jira_get_issue` tool to fetch:
- Current status (To Do, In Progress, Done, etc.)
- Resolution (if any)

Key Jira issues to track:
- **CNF-19031** - Epic for compliance remediations
- **CNF-21212** - H1 (Crypto Policy), H2 (PAM No Empty Passwords)
- **CNF-21326** - H3 (SSHD Empty Passwords)
- **CNF-21196** - M2 (Kernel Sysctl)

### 3. Fetch GitHub PR Status

For each group with a `pr` field, use `mcp__github__pull_request_read` with `method: "get"` to fetch:
- State (open, closed, merged)
- Merge status

Key PRs to track:
- **PR #466** - H3 (SSHD hardening)
- **PR #529** - H1, H2 (Crypto + PAM)

### 4. Derive Status

Apply these rules to determine the derived status:

| PR State | Jira Status | Derived Status |
|----------|-------------|----------------|
| merged   | any         | complete       |
| open     | any         | in_progress    |
| closed   | any         | on_hold        |
| null     | Done/Closed | complete       |
| null     | In Progress | in_progress    |
| null     | Blocked     | on_hold        |
| null     | To Do       | pending        |

### 5. Update Tracking Data

Update `docs/_data/tracking.json` with:
- `jira_status`: Current Jira status string
- `pr_state`: Current PR state (open/merged/closed)
- `status`: Derived status based on rules above
- `last_sync`: ISO timestamp of sync

### 6. Show Summary

Display a summary of changes to the user before saving:

```
Sync Summary:
  H1: in_progress (Jira: In Progress, PR #529: open)
  H2: in_progress (Jira: In Progress, PR #529: open)
  H3: in_progress (Jira: To Do, PR #466: open)
  M2: on_hold (Jira: To Do, no PR)
```

### 7. Confirm and Save

Ask the user to confirm before writing changes.

## Usage Examples

```
/sync-tracking              # Sync all groups
/sync-tracking H3           # Sync specific group
/sync-tracking --dry-run    # Show what would change without saving
```

## Arguments

- `<group_id>` (optional): Sync only a specific group (e.g., H1, M2)
- `--dry-run`: Show changes without saving

## File Locations

- **Tracking data**: `docs/_data/tracking.json`
- **Group pages**: `docs/versions/4.21/groups/*.md`

## Error Handling

- If Jira API fails: Report error, keep existing jira_status
- If GitHub API fails: Report error, keep existing pr_state
- Always show what would change before confirming writes
