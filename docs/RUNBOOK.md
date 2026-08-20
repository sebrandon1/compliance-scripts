# Compliance Dashboard Runbook

This runbook documents the complete workflow for setting up and maintaining compliance tracking for OpenShift versions. Follow these steps when onboarding a new OCP version (e.g., 5.1) or updating existing versions.

Prefer automation where it exists:

```bash
make add-version OCP_VERSION=5.1 SOURCE_VERSION=5.0
make export-compliance OCP_VERSION=5.1
make generate-group-matrix
make backfill-scan-profiles
```

The scaffolder copies version pages, group pages, and `docs/_data/tracking-X_Y.json` from a source version. The rest of this runbook covers what still needs a human: export, Jira/PR tracking, and review.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start Checklist](#quick-start-checklist)
3. [Phase 1: Export Compliance Data](#phase-1-export-compliance-data)
4. [Phase 2: Create Version Pages](#phase-2-create-version-pages)
5. [Phase 3: Create Remediation Groupings](#phase-3-create-remediation-groupings)
6. [Phase 4: Create Individual Group Pages](#phase-4-create-individual-group-pages)
7. [Phase 5: Update Tracking Data](#phase-5-update-tracking-data)
8. [Phase 6: Jira Management](#phase-6-jira-management)
9. [Phase 7: PR Management](#phase-7-pr-management)
10. [Directory Structure Reference](#directory-structure-reference)
11. [Conventions and Standards](#conventions-and-standards)
12. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Access to an OpenShift cluster running the target version with Compliance Operator installed
- `oc` CLI configured with cluster access
- Git access to this repository
- Jira access (for creating/updating tickets)
- GitHub access to openshift-kni/telco-reference (for PRs)

---

## Quick Start Checklist

For a new OCP version (e.g., 5.1), complete these steps in order:

- [ ] Scaffold pages: `make add-version OCP_VERSION=5.1 SOURCE_VERSION=5.0`
- [ ] Export compliance data from cluster (`make export-compliance OCP_VERSION=5.1`)
- [ ] Review `docs/_data/ocp-5_1.json`
- [ ] Review `docs/versions/5.1.md`, `docs/versions/5.1/remediations.md`, and group pages
- [ ] Update `docs/_data/tracking-5_1.json` with Jira/PR info
- [ ] Run `make generate-group-matrix`
- [ ] Run `make backfill-scan-profiles`
- [ ] Update `docs/REMEDIATION_GROUPINGS.md` index
- [ ] Create Jira tickets for new remediation groups
- [ ] Commit and push changes
- [ ] Verify GitHub Pages deployment

---

## Phase 1: Export Compliance Data

### 1.1 Run Compliance Scans

Ensure the Compliance Operator has completed scans:

```bash
# Check scan status
oc get compliancescans -n openshift-compliance

# Wait for scans to complete (should show DONE)
oc get compliancescans -n openshift-compliance -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

### 1.2 Export Compliance Data

Run the export script:

```bash
export KUBECONFIG=/path/to/kubeconfig
export OCP_VERSION=4.22

# Run the export script
./core/export-compliance-data.sh $OCP_VERSION

# Or use make target
make export-compliance OCP_VERSION=4.22
```

This creates `docs/_data/ocp-4_22.json` with:
- Summary statistics (total, passing, failing, manual)
- Failing checks by severity (high, medium, low)
- Passing checks by severity
- Manual checks requiring review

### 1.3 Verify Exported Data

```bash
# Check the generated file
cat docs/_data/ocp-4_22.json | jq '.summary'

# Expected output:
# {
#   "total_checks": 200,
#   "passing": 180,
#   "failing": 15,
#   "manual": 5
# }
```

---

## Phase 2: Create Version Pages

`make add-version` copies these from the source version. Create or edit them by hand only if you are not using the scaffolder.

### 2.1 Create Version Landing Page

Create `docs/versions/4.22.md`:

```markdown
---
layout: version
title: OCP 4.22 Compliance Status
version: "4.22"
---
```

### 2.2 Update Index Page

Add the new version to `docs/index.md`:

```markdown
| [OCP 4.22](versions/4.22.html) | 2025-XX-XX | XX | XX | XX% |
```

### 2.3 Update REMEDIATION_GROUPINGS.md

Add new version to `docs/REMEDIATION_GROUPINGS.md`:

```markdown
| [**OCP 4.22**](versions/4.22/remediations.html) | XX total | Active |
```

---

## Phase 3: Create Remediation Groupings

### 3.1 Analyze Failing Checks

Review the exported data to identify remediation groups:

```bash
# List all failing checks
cat docs/_data/ocp-4_22.json | jq '.remediations.high[].name'
cat docs/_data/ocp-4_22.json | jq '.remediations.medium[].name'
cat docs/_data/ocp-4_22.json | jq '.remediations.low[].name'
```

### 3.2 Group Related Checks

Group checks that can be remediated together:

| Group ID | Category | Typical Checks |
|----------|----------|----------------|
| H1 | Crypto Policy | configure-crypto-policy |
| H2 | PAM Empty Passwords | no-empty-passwords |
| H3 | SSHD Empty Passwords | sshd-disable-empty-passwords |
| M1 | SSHD Configuration | sshd-disable-root-login, sshd-disable-gssapi-auth, etc. |
| M2 | Kernel Sysctl | sysctl-kernel-randomize-va-space, etc. |
| M3-M20 | Audit Rules | Various audit rule checks |
| M10 | API Server Encryption | api-server-encryption-provider-cipher |
| M11 | Ingress TLS | ingress-controller-tls-cipher-suites |
| M12 | Audit Profile | audit-profile-set |
| L1 | SSHD LogLevel | sshd-set-loglevel-info |
| L2 | Sysctl dmesg | sysctl-kernel-dmesg-restrict |

### 3.3 Create Remediations Summary Page

Create `docs/versions/4.22/remediations.md`:

```markdown
---
title: OCP 4.22 Remediation Groupings
---

# OCP 4.22 Remediation Groupings

[← Back to OCP 4.22 Compliance Status](../4.22.html) | [View Detailed Group Pages](groups/)

This document catalogs all compliance remediations for **OCP 4.22**.

> **Tip**: Each group has a [dedicated page](groups/) with detailed implementation examples.

## Quick Summary

From E8 and CIS benchmark scans: **XX total remediations**

| Severity | Groups | Settings | Status |
|----------|--------|----------|--------|
| **HIGH** | X groups | X unique | ... |
| **MEDIUM** | X groups | X unique | ... |
| **LOW** | X groups | X unique | ... |

---

## Remediation Status

| Group | Category | Severity | Count | Status | Jira | PR |
|-------|----------|----------|-------|--------|------|-----|
| [H1](groups/H1.html) | Crypto Policy | HIGH | 1 | 🟡 Pending | - | - |
...

**Status Legend:** 🔵 In Progress | 🟡 Pending | ⚪ On Hold | 🟢 Complete

**Group IDs:** Groups are labeled by severity and sequence number:
- **H** = HIGH severity (H1, H2, H3)
- **M** = MEDIUM severity (M1–M30)
- **L** = LOW severity (L1, L2)
- **MAN** = Manual review (MAN1–MAN5)
```

---

## Phase 4: Create Individual Group Pages

### 4.1 Create Groups Directory

```bash
mkdir -p docs/versions/4.22/groups
```

### 4.2 Group Page Template

Each group page should use this template. Create `docs/versions/4.22/groups/{GROUP_ID}.md`:

```markdown
---
layout: group
title: {GROUP_TITLE}
group_id: {H1|M1|L1|etc.}
version: "4.22"
severity: {HIGH|MEDIUM|LOW}
status: {pending|in_progress|on_hold|complete}
jira: {CNF-XXXXX or empty}
pr: {PR_NUMBER or empty}
prev_group: {PREV_GROUP_ID or empty}
next_group: {NEXT_GROUP_ID or empty}
---

## Overview

{Description of what this remediation does}

## Settings

| Setting | Value | Description |
|---------|-------|-------------|
| `setting_name` | `value` | Description |

## Implementation

{MachineConfig or CRD YAML example}

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
...
```

## Compliance Checks Remediated

| Check | Profile | Description | Docs |
|-------|---------|-------------|------|
| `check-name` | E8/CIS | Description | [📖](https://github.com/ComplianceAsCode/content/tree/master/linux_os/guide/services/ssh/ssh_server/sshd_disable_root_login) |

<div class="source-files">
<h4>Source Remediation Files</h4>
<ul>
<li>severity/rhcos4-e8-worker-check-name.yaml</li>
</ul>
</div>

## Verification

```bash
# Verification command
oc debug node/<node-name> -- chroot /host ...
```

## Security Impact

{Explanation of security benefits}
```

### 4.3 Create Index Page

Create `docs/versions/4.22/groups/index.md`:

```markdown
---
layout: default
title: OCP 4.22 Remediation Groups
---

# OCP 4.22 Remediation Groups

[← Back to OCP 4.22 Compliance Status](../../4.22.html) | [View Summary](../remediations.html)

## HIGH Severity

| Group | Title | Status | Jira | PR |
|-------|-------|--------|------|-----|
| [H1](H1.html) | ... | ... | ... | ... |

## MEDIUM Severity
...

## LOW Severity
...

## Linking to Groups from PRs

Use these URLs in your PR descriptions:

```
https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/H1.html
```
```

### 4.4 Group Navigation Chain

Ensure prev_group/next_group form a complete chain:

```
H1 → H2 → H3 → M1 → … → M30 → L1 → L2 → MAN1 → … → MAN5
```

---

## Phase 5: Update Tracking Data

### 5.1 Update tracking JSON

Each version has its own file: `docs/_data/tracking-4_21.json`, `tracking-4_22.json`, `tracking-5_0.json`. `docs/_data/tracking.json` is the default/latest copy used by some layouts.

Group records look like:

```json
{
  "meta": {
    "jira_base_url": "https://issues.redhat.com/browse/",
    "pr_base_url": "https://github.com/openshift-kni/telco-reference/pull/",
    "compare_base_url": "https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:"
  },
  "groups": {
    "H1": {
      "title": "Crypto Policy",
      "severity": "HIGH",
      "platform": "rhcos",
      "jira": null,
      "pr": null,
      "compare": "compliance/4.22/h1-crypto-policy",
      "status": "verified",
      "prev_group": null,
      "next_group": "H2"
    }
  }
}
```

`compare` is a branch slug appended to `compare_base_url`. GitHub returns 404 after the branch is deleted; leave it for history or set it to `null`.

### 5.2 Status Values

| Status | Meaning | When to Use |
|--------|---------|-------------|
| `pending` | Not started | No Jira or PR created |
| `in_progress` | Active work | Jira created, PR open |
| `on_hold` | Paused | Blocked or deprioritized |
| `complete` | Done | PR merged, verified |

---

## Phase 6: Jira Management

### 6.1 Create Jira Tickets

For each remediation group, create a Jira ticket in CNFCERT project:

**Title Format:**
```
[Compliance] OCP 4.22 - {Group ID}: {Group Title}
```

**Description Template:**
```markdown
## Summary
This ticket tracks the implementation of {Group Title} remediation for OCP 4.22.

## Remediation Group
- **Group ID**: {H1|M1|L1|etc.}
- **Severity**: {HIGH|MEDIUM|LOW}
- **Settings Count**: X

## Documentation
- [Group Details](https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/H1.html)
- [Remediations Summary](https://sebrandon1.github.io/compliance-scripts/versions/4.22/remediations.html)

## Compliance Checks
- check-name-1
- check-name-2
- ...

## Acceptance Criteria
- [ ] MachineConfig/CRD created
- [ ] PR submitted to telco-reference
- [ ] Compliance scan passes after remediation
```

### 6.2 Consolidation Rules

Some groups should be consolidated into a single Jira/PR:

| Consolidated Groups | Single Jira | Reason |
|--------------------|-------------|--------|
| H3 + M1 + L1 | CNF-XXXXX | All SSHD settings in one MachineConfig |
| H1 + H2 | CNF-XXXXX | Non-SSHD HIGH severity items |

### 6.3 Update Group Pages After Jira Creation

After creating Jiras, update the group pages:

```yaml
# In each group's frontmatter
jira: CNF-XXXXX
status: in_progress
```

---

## Phase 7: PR Management

### 7.1 PR Description Template

When creating PRs in openshift-kni/telco-reference:

```markdown
## Summary
This PR implements compliance remediations for OCP 4.22.

## Remediation Groups
- [H1: Crypto Policy](https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/H1.html)
- [H2: PAM Empty Passwords](https://sebrandon1.github.io/compliance-scripts/versions/4.22/groups/H2.html)

## Files Added
- `telco-ran/configuration/machineconfigs/75-crypto-policy-high.yaml`
- `telco-ran/configuration/machineconfigs/75-pam-auth-high.yaml`

## Testing
- [ ] Applied to test cluster
- [ ] Compliance scan passes
- [ ] No node reboots fail

## Jira
- CNF-XXXXX
```

### 7.2 Update After PR Creation

After creating PR, update:

1. Group pages (add `pr: XXX` to frontmatter)
2. `remediations.md` (add PR link to status table)
3. `groups/index.md` (add PR link)
4. Jira ticket (add PR link)

### 7.3 After PR Merge

1. Update status to `complete` in group pages
2. Update Jira status to Done
3. Re-run compliance scan to verify

---

## Directory Structure Reference

```
docs/
├── _config.yml                           # Jekyll config
├── _data/
│   ├── ocp-4_21.json                    # OCP 4.21 compliance data
│   ├── ocp-4_22.json                    # OCP 4.22 compliance data
│   ├── ocp-5_0.json                     # OCP 5.0 compliance data
│   ├── tracking.json                    # Default/latest group tracking
│   ├── tracking-4_21.json               # Per-version tracking
│   ├── tracking-4_22.json
│   ├── tracking-5_0.json
│   ├── group-matrix.json                # Hardened page matrix
│   └── scan-history.json
├── _includes/
│   ├── remediation-table.html           # Failing checks table
│   └── passing-table.html               # Passing checks table
├── _layouts/
│   ├── default.html                     # Base layout
│   ├── version.html                     # Version page layout
│   ├── remediations.html                # Remediations summary layout
│   ├── group.html                       # Group page layout
│   └── hardened.html                    # Hardened accomplishments
├── compare.md                           # Version diff page
├── hardened.md                          # Hardened dashboard
├── index.md                             # Homepage
├── REMEDIATION_GROUPINGS.md             # Version index
├── RUNBOOK.md                           # This file
└── versions/
    ├── 4.21.md                          # OCP 4.21 landing page
    ├── 4.22.md
    ├── 5.0.md
    └── 5.0/groups/                      # H1–H3, M1–M30, L1–L2, MAN1–MAN5
```

---

## Conventions and Standards

### Naming Conventions

| Item | Convention | Example |
|------|------------|---------|
| Data files | `ocp-{version with underscores}.json` | `ocp-4_22.json` |
| Version pages | `{version}.md` | `4.22.md` |
| Group IDs | `{H\|M\|L\|MAN}{number}` | `H1`, `M30`, `L2`, `MAN1` |
| MachineConfig names | `75-{category}-{severity}.yaml` | `75-sshd-hardening.yaml` |

### Status Badges

| Badge | Meaning |
|-------|---------|
| 🔵 In Progress | Active work, PR open |
| 🟡 Pending | Not yet started |
| ⚪ On Hold | Paused/blocked |
| 🟢 Complete | Merged and verified |

### Severity Colors (CSS)

| Severity | Color | Hex |
|----------|-------|-----|
| HIGH | Red | `#dc3545` |
| MEDIUM | Orange | `#fd7e14` |
| LOW | Blue | `#0d6efd` |

### Group Categories

| Category | Typical Groups | Implementation Type |
|----------|----------------|---------------------|
| SSHD | H3, M1, L1 | MachineConfig (consolidated) |
| Crypto | H1 | MachineConfig |
| PAM | H2 | MachineConfig |
| Kernel Sysctl | M2, L2 | MachineConfig |
| Audit Rules | M3–M20 | MachineConfig |
| API Server | M10, M12 | APIServer CRD |
| Ingress | M11 | IngressController CRD |

### Documentation Links

Each compliance check should include a documentation link (📖) in the Compliance Checks Remediated table. Use these URL patterns:

| Check Type | Documentation URL Pattern |
|------------|---------------------------|
| RHCOS SSHD rules | `https://github.com/ComplianceAsCode/content/tree/master/linux_os/guide/services/ssh/ssh_server/{rule_name}` |
| RHCOS Sysctl rules | `https://github.com/ComplianceAsCode/content/tree/master/linux_os/guide/system/permissions/restrictions/{rule_name}` |
| RHCOS Audit time rules | `https://github.com/ComplianceAsCode/content/tree/master/linux_os/guide/auditing/auditd_configure_rules/audit_time_rules/{rule_name}` |
| RHCOS Auditd retention | `https://github.com/ComplianceAsCode/content/tree/master/linux_os/guide/auditing/configure_auditd_data_retention/{rule_name}` |
| OCP4 API Server | `https://docs.openshift.com/container-platform/latest/security/encrypting-etcd.html` |
| OCP4 Ingress TLS | `https://docs.openshift.com/container-platform/latest/security/tls-security-profiles.html` |
| OCP4 Audit Profile | `https://docs.openshift.com/container-platform/latest/security/audit-log-policy-config.html` |
| Fallback (E8 guide) | `https://static.open-scap.org/ssg-guides/ssg-rhcos4-guide-e8.html` |

**Rule Name Mapping:**
- Check names like `rhcos4-e8-worker-sshd-disable-root-login` map to rules like `sshd_disable_root_login`
- Replace hyphens with underscores: `sshd-disable-root-login` → `sshd_disable_root_login`
- Remove the `rhcos4-e8-worker-` prefix to get the base rule name

---

## Troubleshooting

### Jekyll Build Errors

**Tables not rendering in `<details>` blocks:**
Add `markdown="1"` to the details tag:
```html
<details markdown="1">
```

**Page not found after push:**
- Check GitHub Actions for build errors
- Verify file is in `docs/` directory
- Ensure frontmatter is valid YAML

### Data Export Issues

**Empty or missing data:**
```bash
# Verify Compliance Operator is running
oc get pods -n openshift-compliance

# Check for ComplianceCheckResults
oc get compliancecheckresults -n openshift-compliance | wc -l
```

**Permission denied:**
```bash
# Ensure you have cluster-admin or compliance reader role
oc auth can-i get compliancecheckresults -n openshift-compliance
```

### Group Page Issues

**Navigation not working:**
- Verify `prev_group` and `next_group` match actual file names
- Check that the chain is complete (no gaps)

**Jira/PR links not appearing:**
- Ensure frontmatter has correct field names (`jira:`, `pr:`)
- Values should be just the ID, not full URLs

---

## Automation

Already implemented:

1. **`make add-version`** — scaffold version/group pages and tracking JSON
2. **`make export-compliance`** — export scan data from a live cluster
3. **`make generate-group-matrix`** — rebuild the Hardened matrix
4. **`make backfill-scan-profiles`** — fill missing per-profile counts in scan-history.json
5. **`make diff-scans`** — compare two scan exports

Possible follow-ups:

1. **Jira integration** to auto-create tickets from pending groups
2. **PR template generator** based on selected groups
3. **Status sync** between Jira/PR and documentation

---

## Contact

For questions about this runbook or the compliance dashboard:
- Repository: https://github.com/sebrandon1/compliance-scripts
- Dashboard: https://sebrandon1.github.io/compliance-scripts/
