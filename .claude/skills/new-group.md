# New Compliance Remediation Group

Create a new remediation group end-to-end: tracking data, group page, telco-reference branch, and dashboard.

## Inputs

The user provides:
- Group ID (e.g., M31)
- Title (e.g., "Coredump Restrictions")
- List of check names (e.g., coredump-disable-backtraces, coredump-disable-storage)
- Profile source (e.g., rhcos4-moderate, ocp4-moderate, rhcos4-e8)
- Severity (HIGH/MEDIUM/LOW)
- Priority (1-4)
- OCP version (e.g., 4.22, 4.23) — defaults to latest version in `docs/versions/`

## Workflow

Steps 1, 2, and 3 can be done in parallel since they are independent.

### Step 1: Update tracking.json

Add the new group to `docs/_data/tracking.json`:
- Insert into `groups` with proper navigation (prev_group/next_group)
- Fix navigation chain on adjacent groups
- Add entries to the `remediations` section mapping check names to this group
- Status: `pending`

### Step 2: Create Group Page

Create `docs/versions/<VERSION>/groups/<GROUP_ID>.md` with:
- Frontmatter: `layout: group`, `group_id`, `version`
- Overview section describing what the group does
- Profile source (e.g., "NIST 800-53 Moderate (`rhcos4-moderate`)")
- Checks table: `| Check | Description |`
- Verification command in a bash code block

### Step 3: Create telco-reference Branch

In `~/Repositories/go/src/github.com/openshift-kni/telco-reference`:

1. Sync fork: `git checkout main && git pull upstream main --rebase && git push origin main -f`
2. Create branch: `compliance/<VERSION>/<slug>`
3. Find source remediation YAMLs in `complianceremediations/`
4. Create separate master/worker YAML files:
   - Inject `metadata.name` and `metadata.labels` (Moderate YAMLs lack these)
   - Set Ignition version to match cluster (3.5.0 for OCP 4.22)
   - Add plaintext comments above URL-encoded `source:` showing actual config lines only
   - No documentation comments (no URLs, Jira links, group IDs)
5. Commit (1 commit only), push
6. If rebase conflicts occur, reset branch and recreate from main

### Step 4: Update Dashboard Index

Add the new group to `docs/versions/<VERSION>/groups/index.md` in the correct severity section with a compare link.

### Step 5: Lint, Commit, and Push

Run `make lint` to verify, then commit all compliance-scripts changes and push to main.

## Important Notes

- Separate master/worker files, never multi-doc YAML with same name
- File naming: `75-<slug>-{master,worker}.yaml` for MCs, `75-<slug>.yaml` for CRDs
- Subdirs: `audit/`, `sysctl/`, `sshd/`, `misc/` for MCs; `crds/` for non-MC manifests
- telco-reference branches must have exactly 1 commit
