---
title: OCP 4.21 Remediation Groupings
---

# OCP 4.21 Remediation Groupings

[← Back to OCP 4.21 Compliance Status](../4.21.html) | [View Detailed Group Pages](groups/)

This document catalogs all compliance remediations for **OCP 4.21**, collected from the OpenShift Compliance Operator and organized by severity (HIGH, MEDIUM, LOW).

> **Tip**: Each group has a [dedicated page](groups/) with detailed implementation examples that you can link directly from PRs.

<div class="filter-bar">
  <div class="filter-search">
    <input type="text" id="table-search" placeholder="Search remediations..." onkeyup="filterTables()">
  </div>
  <div class="filter-buttons">
    <button class="filter-btn active" data-filter="all" onclick="setStatusFilter('all')">All</button>
    <button class="filter-btn" data-filter="pending" onclick="setStatusFilter('pending')">🟡 Pending</button>
    <button class="filter-btn" data-filter="in_progress" onclick="setStatusFilter('in_progress')">🔵 In Progress</button>
    <button class="filter-btn" data-filter="on_hold" onclick="setStatusFilter('on_hold')">⚪ On Hold</button>
    <button class="filter-btn" data-filter="complete" onclick="setStatusFilter('complete')">🟢 Complete</button>
  </div>
  <div class="filter-counts" id="filter-counts"></div>
</div>

## Quick Summary

From E8 (Essential Eight) and CIS benchmark scans: **82 total remediations**

| Severity | Groups | Settings | Status |
|----------|--------|----------|--------|
| **HIGH** | 3 groups | 3 unique | 3 In Progress |
| **MEDIUM** | 12 groups | 36 unique | 1 On Hold, 11 Pending |
| **LOW** | 2 groups | 2 unique | 2 Pending |

---

## Remediation Status

<table class="status-table">
  <thead>
    <tr>
      <th style="width: 60px;">Group</th>
      <th>Category</th>
      <th style="width: 80px;">Severity</th>
      <th style="width: 50px; text-align: center;">Count</th>
      <th style="width: 110px;">Status</th>
      <th style="width: 50px; text-align: center;">Compare</th>
      <th style="width: 100px;">Jira</th>
      <th style="width: 70px;">PR</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="groups/H1.html" class="group-id">H1</a></td>
      <td>Crypto Policy</td>
      <td><span class="severity-pill high">HIGH</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill in-progress">🔵 In Progress</span></td>
      <td style="text-align: center;">-</td>
      <td><a href="https://issues.redhat.com/browse/CNF-21212" class="jira-badge">CNF-21212</a></td>
      <td><a href="https://github.com/openshift-kni/telco-reference/pull/529" class="pr-badge">#529</a></td>
    </tr>
    <tr>
      <td><a href="groups/H2.html" class="group-id">H2</a></td>
      <td>PAM Empty Passwords</td>
      <td><span class="severity-pill high">HIGH</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill in-progress">🔵 In Progress</span></td>
      <td style="text-align: center;">-</td>
      <td><a href="https://issues.redhat.com/browse/CNF-21212" class="jira-badge">CNF-21212</a></td>
      <td><a href="https://github.com/openshift-kni/telco-reference/pull/529" class="pr-badge">#529</a></td>
    </tr>
    <tr>
      <td><a href="groups/H3.html" class="group-id">H3</a></td>
      <td>SSHD Empty Passwords</td>
      <td><span class="severity-pill high">HIGH</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill in-progress">🔵 In Progress</span></td>
      <td style="text-align: center;">-</td>
      <td><a href="https://issues.redhat.com/browse/CNF-19031" class="jira-badge">CNF-19031</a></td>
      <td><a href="https://github.com/openshift-kni/telco-reference/pull/466" class="pr-badge">#466</a></td>
    </tr>
    <tr>
      <td><a href="groups/M1.html" class="group-id">M1</a></td>
      <td>SSHD Configuration</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">7</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:m1-sshd-medium-hardening" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M2.html" class="group-id">M2</a></td>
      <td>Kernel Sysctl</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">4</td>
      <td><span class="status-pill on-hold">⚪ On Hold</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m2-kernel-sysctl" class="compare-btn">📦</a></td>
      <td><a href="https://issues.redhat.com/browse/CNF-21196" class="jira-badge">CNF-21196</a></td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M3.html" class="group-id">M3</a></td>
      <td>Audit DAC</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">2</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m3-audit-dac" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M4.html" class="group-id">M4</a></td>
      <td>Audit SELinux</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">6</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m4-audit-selinux" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M5.html" class="group-id">M5</a></td>
      <td>Audit Modules</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">3</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m5-audit-modules" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M6.html" class="group-id">M6</a></td>
      <td>Audit Time</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">5</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m6-audit-time" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M7.html" class="group-id">M7</a></td>
      <td>Audit Auth</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">5</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m7-audit-login" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M8.html" class="group-id">M8</a></td>
      <td>Audit Network</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m8-audit-network" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M9.html" class="group-id">M9</a></td>
      <td>Auditd Config</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m9-auditd-config" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M10.html" class="group-id">M10</a></td>
      <td>API Encryption</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">2</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m10-api-encryption" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M11.html" class="group-id">M11</a></td>
      <td>Ingress TLS</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m11-ingress-tls" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/M12.html" class="group-id">M12</a></td>
      <td>Audit Profile</td>
      <td><span class="severity-pill medium">MEDIUM</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m12-audit-profile" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/L1.html" class="group-id">L1</a></td>
      <td>SSHD LogLevel</td>
      <td><span class="severity-pill low">LOW</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/l1-sshd-loglevel" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
    <tr>
      <td><a href="groups/L2.html" class="group-id">L2</a></td>
      <td>Sysctl dmesg</td>
      <td><span class="severity-pill low">LOW</span></td>
      <td style="text-align: center;">1</td>
      <td><span class="status-pill pending">🟡 Pending</span></td>
      <td style="text-align: center;"><a href="https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/l2-sysctl-dmesg" class="compare-btn">📦</a></td>
      <td>-</td>
      <td>-</td>
    </tr>
  </tbody>
</table>

<div class="status-legend">
  <span class="status-pill in-progress">🔵 In Progress</span>
  <span class="status-pill pending">🟡 Pending</span>
  <span class="status-pill on-hold">⚪ On Hold</span>
  <span class="status-pill complete">🟢 Complete</span>
</div>

**Group IDs:** Groups are labeled by severity and sequence number:
- **H** = HIGH severity (H1, H2, H3)
- **M** = MEDIUM severity (M1-M12)
- **L** = LOW severity (L1, L2)

---

## HIGH Severity Remediations

<details markdown="1" open>
<summary><strong>H1: Crypto Policy</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/529">PR #529</a></summary>

**File**: `75-crypto-policy-high.yaml`
**Jira**: [CNF-21212](https://issues.redhat.com/browse/CNF-21212)

| Setting | Value | Description |
|---------|-------|-------------|
| crypto-policy | DEFAULT:NO-SHA1 | System-wide crypto policy without SHA1 |

**Source Files**:
- [`high/rhcos4-e8-worker-configure-crypto-policy.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-worker-configure-crypto-policy.yaml)
- [`high/rhcos4-e8-master-configure-crypto-policy.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-master-configure-crypto-policy.yaml)

</details>

<details markdown="1" open>
<summary><strong>H2: PAM Empty Passwords</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/529">PR #529</a></summary>

**File**: `75-pam-auth-high.yaml`
**Jira**: [CNF-21212](https://issues.redhat.com/browse/CNF-21212)

| Setting | Description |
|---------|-------------|
| no-empty-passwords | Disable nullok in PAM system-auth and password-auth |

**Source Files**:
- [`high/rhcos4-e8-worker-no-empty-passwords.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-worker-no-empty-passwords.yaml)
- [`high/rhcos4-e8-master-no-empty-passwords.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-master-no-empty-passwords.yaml)

</details>

<details markdown="1" open>
<summary><strong>H3: SSHD Empty Passwords</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/466">PR #466</a></summary>

**File**: `75-sshd-hardening.yaml` (consolidated with M1, L1)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| PermitEmptyPasswords | no | Prevent SSH login with empty passwords |

**Source Files**:
- [`high/rhcos4-e8-worker-sshd-disable-empty-passwords.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-worker-sshd-disable-empty-passwords.yaml)
- [`high/rhcos4-e8-master-sshd-disable-empty-passwords.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/high/rhcos4-e8-master-sshd-disable-empty-passwords.yaml)

> **Note**: This HIGH severity SSHD setting is consolidated into PR #466 along with MEDIUM (M1) and LOW (L1) SSHD settings.

</details>

<details markdown="1">
<summary><strong>Manual HIGH Checks</strong> — No auto-remediation available</summary>

These HIGH severity checks require manual intervention:

| Check | Type | Description |
|-------|------|-------------|
| `ocp4-cis-configure-network-policies-namespaces` | CIS | Ensure all application namespaces have NetworkPolicy defined |
| `ocp4-cis-rbac-least-privilege` | CIS | Review RBAC permissions for least privilege |

</details>

---

## MEDIUM Severity Remediations

<details markdown="1" open>
<summary><strong>M1: SSHD Configuration</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/466">PR #466</a></summary>

**File**: `75-sshd-hardening.yaml` (consolidated with H3, L1)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)
**Count**: 7 settings

| Setting | Value | Description |
|---------|-------|-------------|
| PermitRootLogin | no | Disable direct root SSH access |
| GSSAPIAuthentication | no | Disable GSSAPI authentication |
| IgnoreRhosts | yes | Disable rhost authentication |
| IgnoreUserKnownHosts | yes | Ignore user's known_hosts file |
| PermitUserEnvironment | no | Block user environment variable passing |
| StrictModes | yes | Enable strict mode checking |
| PrintLastLog | yes | Display last login information |

<details markdown="1">
<summary>Source Files (7)</summary>

- [`medium/rhcos4-e8-worker-sshd-disable-root-login.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-disable-root-login.yaml)
- [`medium/rhcos4-e8-worker-sshd-disable-gssapi-auth.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-disable-gssapi-auth.yaml)
- [`medium/rhcos4-e8-worker-sshd-disable-rhosts.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-disable-rhosts.yaml)
- [`medium/rhcos4-e8-worker-sshd-disable-user-known-hosts.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-disable-user-known-hosts.yaml)
- [`medium/rhcos4-e8-worker-sshd-do-not-permit-user-env.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-do-not-permit-user-env.yaml)
- [`medium/rhcos4-e8-worker-sshd-enable-strictmodes.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-enable-strictmodes.yaml)
- [`medium/rhcos4-e8-worker-sshd-print-last-log.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sshd-print-last-log.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M2: Kernel Hardening (Sysctl)</strong> — ⚪ On Hold — PR #528 closed</summary>

**File**: `75-sysctl-medium.yaml`
**Jira**: [CNF-21196](https://issues.redhat.com/browse/CNF-21196)
**Count**: 4 settings

| Setting | Value | Description |
|---------|-------|-------------|
| kernel.randomize_va_space | 2 | Full ASLR - randomizes memory layout |
| kernel.unprivileged_bpf_disabled | 1 | Prevent BPF-based privilege escalation |
| kernel.yama.ptrace_scope | 1 | Restrict ptrace to parent-child processes |
| net.core.bpf_jit_harden | 2 | Harden BPF JIT against spraying attacks |

<details markdown="1">
<summary>Source Files (4)</summary>

- [`medium/rhcos4-e8-worker-sysctl-kernel-randomize-va-space.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sysctl-kernel-randomize-va-space.yaml)
- [`medium/rhcos4-e8-worker-sysctl-kernel-unprivileged-bpf-disabled.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sysctl-kernel-unprivileged-bpf-disabled.yaml)
- [`medium/rhcos4-e8-worker-sysctl-kernel-yama-ptrace-scope.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sysctl-kernel-yama-ptrace-scope.yaml)
- [`medium/rhcos4-e8-worker-sysctl-net-core-bpf-jit-harden.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-sysctl-net-core-bpf-jit-harden.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M3: Audit Rules - DAC Modifications</strong> — 🟡 Pending</summary>

**File**: `75-audit-dac-medium.yaml`
**Count**: 2 settings

| Rule | Description |
|------|-------------|
| chmod | Audit file permission changes via chmod |
| chown | Audit file ownership changes via chown |

<details markdown="1">
<summary>Source Files (2)</summary>

- [`medium/rhcos4-e8-worker-audit-rules-dac-modification-chmod.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-dac-modification-chmod.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-dac-modification-chown.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-dac-modification-chown.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M4: Audit Rules - SELinux</strong> — 🟡 Pending</summary>

**File**: `75-audit-privilege-medium.yaml`
**Count**: 6 settings

| Rule | Description |
|------|-------------|
| chcon | Audit SELinux context changes |
| restorecon | Audit SELinux context restoration |
| semanage | Audit SELinux management commands |
| setfiles | Audit SELinux file labeling |
| setsebool | Audit SELinux boolean changes |
| seunshare | Audit SELinux unshare operations |

<details markdown="1">
<summary>Source Files (6)</summary>

- [`medium/rhcos4-e8-worker-audit-rules-execution-chcon.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-chcon.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-execution-restorecon.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-restorecon.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-execution-semanage.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-semanage.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-execution-setfiles.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-setfiles.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-execution-setsebool.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-setsebool.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-execution-seunshare.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-execution-seunshare.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M5: Audit Rules - Kernel Modules</strong> — 🟡 Pending</summary>

**File**: `75-audit-modules-medium.yaml`
**Count**: 3 settings

| Rule | Description |
|------|-------------|
| delete_module | Audit kernel module unloading (rmmod) |
| finit_module | Audit kernel module loading (finit) |
| init_module | Audit kernel module loading (init) |

<details markdown="1">
<summary>Source Files (3)</summary>

- [`medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-delete.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-delete.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-finit.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-finit.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-init.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-init.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M6: Audit Rules - Time Modifications</strong> — 🟡 Pending</summary>

**File**: `75-audit-time-medium.yaml`
**Count**: 5 settings

| Rule | Description |
|------|-------------|
| adjtimex | Audit fine-grained time adjustments |
| clock_settime | Audit clock setting operations |
| settimeofday | Audit time-of-day changes |
| stime | Audit legacy time setting |
| /etc/localtime | Watch for localtime file changes |

<details markdown="1">
<summary>Source Files (5)</summary>

- [`medium/rhcos4-e8-worker-audit-rules-time-adjtimex.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-time-adjtimex.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-time-clock-settime.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-time-clock-settime.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-time-settimeofday.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-time-settimeofday.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-time-stime.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-time-stime.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-time-watch-localtime.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-time-watch-localtime.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M7: Audit Rules - Login Monitoring</strong> — 🟡 Pending</summary>

**File**: `75-audit-auth-medium.yaml`
**Count**: 5 settings

| Rule | Description |
|------|-------------|
| faillock | Monitor failed login attempts |
| lastlog | Monitor last login records |
| tallylog | Monitor login attempt tallies |
| sudoers | Monitor sudo configuration changes |
| usergroup | Monitor /etc/passwd, /etc/group, /etc/shadow changes |

<details markdown="1">
<summary>Source Files (5)</summary>

- [`medium/rhcos4-e8-worker-audit-rules-login-events-faillock.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-login-events-faillock.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-login-events-lastlog.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-login-events-lastlog.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-login-events-tallylog.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-login-events-tallylog.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-sysadmin-actions.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-sysadmin-actions.yaml)
- [`medium/rhcos4-e8-worker-audit-rules-usergroup-modification.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-usergroup-modification.yaml)

</details>
</details>

<details markdown="1">
<summary><strong>M8: Audit Rules - Network Config</strong> — 🟡 Pending</summary>

**File**: `75-audit-network-medium.yaml`
**Count**: 1 setting

| Rule | Description |
|------|-------------|
| network_modification | Audit sethostname, setdomainname syscalls |

**Source Files**:
- [`medium/rhcos4-e8-worker-audit-rules-networkconfig-modification.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-audit-rules-networkconfig-modification.yaml)

</details>

<details markdown="1">
<summary><strong>M9: Auditd Configuration</strong> — 🟡 Pending</summary>

**File**: `75-auditd-config-medium.yaml`
**Count**: 1 setting

| Setting | Value | Description |
|---------|-------|-------------|
| name_format | hostname | Log hostname in audit records |

**Source Files**:
- [`medium/rhcos4-e8-worker-auditd-name-format.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/rhcos4-e8-worker-auditd-name-format.yaml)

</details>

<details markdown="1">
<summary><strong>M10: API Server Encryption</strong> — 🟡 Pending</summary>

**Type**: APIServer CRD
**File**: `75-api-server-encryption-medium.yaml`
**Count**: 2 remediations

| Setting | Value | Description |
|---------|-------|-------------|
| encryption.type | aescbc | Enable AES-CBC encryption at rest |

**Source Files**:
- [`medium/ocp4-cis-api-server-encryption-provider-cipher.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/ocp4-cis-api-server-encryption-provider-cipher.yaml)
- [`medium/ocp4-e8-api-server-encryption-provider-cipher.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/ocp4-e8-api-server-encryption-provider-cipher.yaml)

</details>

<details markdown="1">
<summary><strong>M11: Ingress TLS Ciphers</strong> — 🟡 Pending</summary>

**Type**: IngressController CRD
**File**: `75-ingress-tls-medium.yaml`
**Count**: 1 remediation

| Setting | Description |
|---------|-------------|
| tlsSecurityProfile | Custom TLS profile with specific cipher suites |

**Source Files**:
- [`medium/ocp4-cis-ingress-controller-tls-cipher-suites.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/ocp4-cis-ingress-controller-tls-cipher-suites.yaml)

</details>

<details markdown="1">
<summary><strong>M12: Audit Profile</strong> — 🟡 Pending</summary>

**Type**: APIServer CRD
**File**: `75-audit-profile-medium.yaml`
**Count**: 1 remediation

| Setting | Value | Description |
|---------|-------|-------------|
| audit.profile | WriteRequestBodies | Enhanced audit logging |

**Source Files**:
- [`medium/ocp4-cis-audit-profile-set.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/medium/ocp4-cis-audit-profile-set.yaml)

</details>

---

## LOW Severity Remediations

<details markdown="1" open>
<summary><strong>L1: SSHD LogLevel</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/466">PR #466</a></summary>

**File**: `75-sshd-hardening.yaml` (consolidated with H3, M1)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| LogLevel | INFO | Set SSH logging to INFO level |

**Source Files**:
- [`low/rhcos4-e8-worker-sshd-set-loglevel-info.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/low/rhcos4-e8-worker-sshd-set-loglevel-info.yaml)
- [`low/rhcos4-e8-master-sshd-set-loglevel-info.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/low/rhcos4-e8-master-sshd-set-loglevel-info.yaml)

</details>

<details markdown="1">
<summary><strong>L2: Sysctl dmesg_restrict</strong> — 🟡 Pending</summary>

**File**: `75-sysctl-low.yaml`

| Setting | Value | Description |
|---------|-------|-------------|
| kernel.dmesg_restrict | 1 | Restrict kernel log access to privileged users |

**Source Files**:
- [`low/rhcos4-e8-worker-sysctl-kernel-dmesg-restrict.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/low/rhcos4-e8-worker-sysctl-kernel-dmesg-restrict.yaml)
- [`low/rhcos4-e8-master-sysctl-kernel-dmesg-restrict.yaml`](https://github.com/sebrandon1/compliance-scripts/blob/main/complianceremediations/low/rhcos4-e8-master-sysctl-kernel-dmesg-restrict.yaml)

</details>

---

## Notes

- **Severity Source**: Severity levels come directly from Compliance Operator's ComplianceCheckResult objects
- **File Naming**: Use `75-<category>-<severity>.yaml` pattern
- **SSHD Consolidation**: All SSHD settings (H3, M1, L1) consolidated into `75-sshd-hardening.yaml` in PR #466
- **PR #529**: Non-SSHD HIGH severity items (crypto-policy, PAM)
- **PR #466**: All SSHD hardening (HIGH + MEDIUM + LOW)

<script>
var currentFilter = 'all';
var searchTerm = '';

function setStatusFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-btn').forEach(btn => btn.classList.remove('active'));
  document.querySelector('[data-filter="' + filter + '"]').classList.add('active');
  filterTables();
}

function filterTables() {
  searchTerm = document.getElementById('table-search').value.toLowerCase();
  var tables = document.querySelectorAll('table');
  var visibleCount = 0;
  var totalCount = 0;

  tables.forEach(function(table) {
    var rows = table.querySelectorAll('tbody tr, tr:not(:first-child)');
    rows.forEach(function(row) {
      if (row.querySelector('th')) return;
      totalCount++;
      var text = row.textContent.toLowerCase();
      var statusMatch = text.match(/(pending|in progress|on hold|complete)/i);
      var status = statusMatch ? statusMatch[0].toLowerCase() : '';

      var matchesSearch = searchTerm === '' || text.includes(searchTerm);
      var matchesFilter = currentFilter === 'all' ||
        (currentFilter === 'pending' && status === 'pending') ||
        (currentFilter === 'in_progress' && status === 'in progress') ||
        (currentFilter === 'on_hold' && status === 'on hold') ||
        (currentFilter === 'complete' && status === 'complete');

      if (matchesSearch && matchesFilter) {
        row.style.display = '';
        visibleCount++;
      } else {
        row.style.display = 'none';
      }
    });
  });

  document.getElementById('filter-counts').textContent =
    visibleCount === totalCount ? '' : 'Showing ' + visibleCount + ' of ' + totalCount;
}
</script>
