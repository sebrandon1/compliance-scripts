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

## Workflow

### Step 1: Update tracking.json

Add the new group to `docs/_data/tracking.json`:
- Insert into the `groups` object with proper navigation (prev_group/next_group)
- Fix the navigation chain on adjacent groups
- Status: `pending`

### Step 2: Create Group Page

Create `docs/versions/4.22/groups/<GROUP_ID>.md` with:
- Frontmatter: layout, group_id, version
- Overview section describing what the group does
- Profile source (e.g., "NIST 800-53 Moderate (`rhcos4-moderate`)")
- Checks table with check names and descriptions
- Verification command

Reference existing group pages for format (e.g., M26.md, M21.md).

### Step 3: Create telco-reference Branch

In `~/Repositories/go/src/github.com/openshift-kni/telco-reference`:

1. Sync fork: `git checkout main && git pull upstream main --rebase && git push origin main`
2. Create branch: `compliance/4.22/<slug>`
3. Find source remediation YAMLs in `complianceremediations/`
4. Create separate master/worker YAML files with:
   - Injected metadata (name, labels, role)
   - Ignition version 3.5.0
   - Plaintext comments above URL-encoded `source:` lines
   - No documentation comments (no URLs, Jira links, group IDs)
5. Commit (1 commit only), push

### Step 4: Update Dashboard Index

Add the new group to `docs/versions/4.22/groups/index.md` in the correct severity section with a compare link.

### Step 5: Commit and Push

Commit all compliance-scripts changes and push to main.

## Important Notes

- Moderate remediation YAMLs lack metadata — must inject `metadata.name`, `metadata.labels`
- Use separate master/worker files, never multi-doc YAML
- telco-reference branches must have exactly 1 commit
- File naming: `75-<slug>-{master,worker}.yaml` for MCs, `75-<slug>.yaml` for CRDs
- Subdirs: audit/, sysctl/, sshd/, misc/ for MCs; crds/ for non-MC manifests
