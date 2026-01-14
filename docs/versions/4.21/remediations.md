---
title: OCP 4.21 Remediation Groupings
---

# OCP 4.21 Remediation Groupings

[← Back to OCP 4.21 Compliance Status](../4.21.html) | [View Detailed Group Pages](groups/)

This document catalogs all compliance remediations for **OCP 4.21**, collected from the OpenShift Compliance Operator and organized by severity (HIGH, MEDIUM, LOW).

> **Tip**: Each group has a [dedicated page](groups/) with detailed implementation examples that you can link directly from PRs.

## Quick Summary

From E8 (Essential Eight) and CIS benchmark scans: **82 total remediations**

| Severity | Groups | Settings | Status |
|----------|--------|----------|--------|
| **HIGH** | 3 groups | 3 unique | 3 In Progress |
| **MEDIUM** | 12 groups | 36 unique | 1 On Hold, 11 Pending |
| **LOW** | 2 groups | 2 unique | 2 Pending |

---

## Remediation Status

| Group | Category | Severity | Count | Status | Jira | PR |
|-------|----------|----------|-------|--------|------|-----|
| [H1](groups/H1.html) | Crypto Policy | HIGH | 1 | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H2](groups/H2.html) | PAM Empty Passwords | HIGH | 1 | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H3](groups/H3.html) | SSHD Empty Passwords | HIGH | 1 | 🔵 In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| [M1](groups/M1.html) | SSHD Configuration | MEDIUM | 7 | 🟡 Pending | - | - |
| [M2](groups/M2.html) | Kernel Sysctl | MEDIUM | 4 | ⚪ On Hold | [CNF-21196](https://issues.redhat.com/browse/CNF-21196) | - |
| [M3](groups/M3.html) | Audit DAC | MEDIUM | 2 | 🟡 Pending | - | - |
| [M4](groups/M4.html) | Audit SELinux | MEDIUM | 6 | 🟡 Pending | - | - |
| [M5](groups/M5.html) | Audit Modules | MEDIUM | 3 | 🟡 Pending | - | - |
| [M6](groups/M6.html) | Audit Time | MEDIUM | 5 | 🟡 Pending | - | - |
| [M7](groups/M7.html) | Audit Auth | MEDIUM | 5 | 🟡 Pending | - | - |
| [M8](groups/M8.html) | Audit Network | MEDIUM | 1 | 🟡 Pending | - | - |
| [M9](groups/M9.html) | Auditd Config | MEDIUM | 1 | 🟡 Pending | - | - |
| [M10](groups/M10.html) | API Encryption | MEDIUM | 2 | 🟡 Pending | - | - |
| [M11](groups/M11.html) | Ingress TLS | MEDIUM | 1 | 🟡 Pending | - | - |
| [M12](groups/M12.html) | Audit Profile | MEDIUM | 1 | 🟡 Pending | - | - |
| [L1](groups/L1.html) | SSHD LogLevel | LOW | 1 | 🟡 Pending | - | - |
| [L2](groups/L2.html) | Sysctl dmesg | LOW | 1 | 🟡 Pending | - | - |

**Status Legend:** 🔵 In Progress | 🟡 Pending | ⚪ On Hold | 🟢 Complete

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
- `high/rhcos4-e8-worker-configure-crypto-policy.yaml`
- `high/rhcos4-e8-master-configure-crypto-policy.yaml`

</details>

<details markdown="1" open>
<summary><strong>H2: PAM Empty Passwords</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/529">PR #529</a></summary>

**File**: `75-pam-auth-high.yaml`
**Jira**: [CNF-21212](https://issues.redhat.com/browse/CNF-21212)

| Setting | Description |
|---------|-------------|
| no-empty-passwords | Disable nullok in PAM system-auth and password-auth |

**Source Files**:
- `high/rhcos4-e8-worker-no-empty-passwords.yaml`
- `high/rhcos4-e8-master-no-empty-passwords.yaml`

</details>

<details markdown="1" open>
<summary><strong>H3: SSHD Empty Passwords</strong> — 🔵 In Progress — <a href="https://github.com/openshift-kni/telco-reference/pull/466">PR #466</a></summary>

**File**: `75-sshd-hardening.yaml` (consolidated with M1, L1)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| PermitEmptyPasswords | no | Prevent SSH login with empty passwords |

**Source Files**:
- `high/rhcos4-e8-worker-sshd-disable-empty-passwords.yaml`
- `high/rhcos4-e8-master-sshd-disable-empty-passwords.yaml`

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

- `medium/rhcos4-e8-worker-sshd-disable-root-login.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-gssapi-auth.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-rhosts.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-user-known-hosts.yaml`
- `medium/rhcos4-e8-worker-sshd-do-not-permit-user-env.yaml`
- `medium/rhcos4-e8-worker-sshd-enable-strictmodes.yaml`
- `medium/rhcos4-e8-worker-sshd-print-last-log.yaml`

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

- `medium/rhcos4-e8-worker-sysctl-kernel-randomize-va-space.yaml`
- `medium/rhcos4-e8-worker-sysctl-kernel-unprivileged-bpf-disabled.yaml`
- `medium/rhcos4-e8-worker-sysctl-kernel-yama-ptrace-scope.yaml`
- `medium/rhcos4-e8-worker-sysctl-net-core-bpf-jit-harden.yaml`

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

- `medium/rhcos4-e8-worker-audit-rules-dac-modification-chmod.yaml`
- `medium/rhcos4-e8-worker-audit-rules-dac-modification-chown.yaml`

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

- `medium/rhcos4-e8-worker-audit-rules-execution-chcon.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-restorecon.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-semanage.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-setfiles.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-setsebool.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-seunshare.yaml`

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

- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-delete.yaml`
- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-finit.yaml`
- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-init.yaml`

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

- `medium/rhcos4-e8-worker-audit-rules-time-adjtimex.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-clock-settime.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-settimeofday.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-stime.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-watch-localtime.yaml`

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

- `medium/rhcos4-e8-worker-audit-rules-login-events-faillock.yaml`
- `medium/rhcos4-e8-worker-audit-rules-login-events-lastlog.yaml`
- `medium/rhcos4-e8-worker-audit-rules-login-events-tallylog.yaml`
- `medium/rhcos4-e8-worker-audit-rules-sysadmin-actions.yaml`
- `medium/rhcos4-e8-worker-audit-rules-usergroup-modification.yaml`

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
- `medium/rhcos4-e8-worker-audit-rules-networkconfig-modification.yaml`

</details>

<details markdown="1">
<summary><strong>M9: Auditd Configuration</strong> — 🟡 Pending</summary>

**File**: `75-auditd-config-medium.yaml`
**Count**: 1 setting

| Setting | Value | Description |
|---------|-------|-------------|
| name_format | hostname | Log hostname in audit records |

**Source Files**:
- `medium/rhcos4-e8-worker-auditd-name-format.yaml`

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
- `medium/ocp4-cis-api-server-encryption-provider-cipher.yaml`
- `medium/ocp4-e8-api-server-encryption-provider-cipher.yaml`

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
- `medium/ocp4-cis-ingress-controller-tls-cipher-suites.yaml`

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
- `medium/ocp4-cis-audit-profile-set.yaml`

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
- `low/rhcos4-e8-worker-sshd-set-loglevel-info.yaml`
- `low/rhcos4-e8-master-sshd-set-loglevel-info.yaml`

</details>

<details markdown="1">
<summary><strong>L2: Sysctl dmesg_restrict</strong> — 🟡 Pending</summary>

**File**: `75-sysctl-low.yaml`

| Setting | Value | Description |
|---------|-------|-------------|
| kernel.dmesg_restrict | 1 | Restrict kernel log access to privileged users |

**Source Files**:
- `low/rhcos4-e8-worker-sysctl-kernel-dmesg-restrict.yaml`
- `low/rhcos4-e8-master-sysctl-kernel-dmesg-restrict.yaml`

</details>

---

## Notes

- **Severity Source**: Severity levels come directly from Compliance Operator's ComplianceCheckResult objects
- **File Naming**: Use `75-<category>-<severity>.yaml` pattern
- **SSHD Consolidation**: All SSHD settings (H3, M1, L1) consolidated into `75-sshd-hardening.yaml` in PR #466
- **PR #529**: Non-SSHD HIGH severity items (crypto-policy, PAM)
- **PR #466**: All SSHD hardening (HIGH + MEDIUM + LOW)
