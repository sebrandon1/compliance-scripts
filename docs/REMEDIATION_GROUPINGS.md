# Compliance Remediation Groupings

This document catalogs all compliance remediations collected from the OpenShift Compliance Operator, organized by **actual Compliance Operator severity** (HIGH, MEDIUM, LOW).

## Overview

From E8 (Essential Eight) and CIS benchmark scans, we identified **82 total remediations**:
- **HIGH**: 6 files (3 unique settings)
- **MEDIUM**: 72 files (36 unique settings)
- **LOW**: 4 files (2 unique settings)

---

## HIGH Severity Remediations

> **Verification Note**: All HIGH severity remediations have been verified against the cluster.
> - 3 auto-remediations collected (H1-H3)
> - 2 manual checks exist (network policies, RBAC) - no auto-remediation available
> - SSHD empty passwords check is PASSING but config included for explicit hardening

### Group H1: Crypto Policy
**Severity**: HIGH
**File**: `75-crypto-policy-high.yaml`
**Count**: 1 setting (master/worker)
**Status**: In Progress - [PR #529](https://github.com/openshift-kni/telco-reference/pull/529)
**Jira**: [CNF-21212](https://issues.redhat.com/browse/CNF-21212)

| Setting | Value | Description |
|---------|-------|-------------|
| crypto-policy | DEFAULT:NO-SHA1 | System-wide crypto policy without SHA1 |

**Source Files**:
- `high/rhcos4-e8-worker-configure-crypto-policy.yaml`
- `high/rhcos4-e8-master-configure-crypto-policy.yaml`

---

### Group H2: PAM Empty Passwords
**Severity**: HIGH
**File**: `75-pam-auth-high.yaml`
**Count**: 1 setting (master/worker)
**Status**: In Progress - [PR #529](https://github.com/openshift-kni/telco-reference/pull/529)
**Jira**: [CNF-21212](https://issues.redhat.com/browse/CNF-21212)

| Setting | Description |
|---------|-------------|
| no-empty-passwords | Disable nullok in PAM system-auth and password-auth |

**Source Files**:
- `high/rhcos4-e8-worker-no-empty-passwords.yaml`
- `high/rhcos4-e8-master-no-empty-passwords.yaml`

---

### Group H3: SSHD Empty Passwords
**Severity**: HIGH
**File**: `75-sshd-hardening.yaml` (consolidated with M1, L1)
**Count**: 1 setting (master/worker)
**Status**: In Progress - [PR #466](https://github.com/openshift-kni/telco-reference/pull/466)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| PermitEmptyPasswords | no | Prevent SSH login with empty passwords |

**Source Files**:
- `high/rhcos4-e8-worker-sshd-disable-empty-passwords.yaml`
- `high/rhcos4-e8-master-sshd-disable-empty-passwords.yaml`

> **Note**: This HIGH severity SSHD setting is consolidated into PR #466 along with MEDIUM (M1) and LOW (L1) SSHD settings.

---

### Manual HIGH Severity Checks (No Auto-Remediation)

These HIGH severity checks require manual intervention - no MachineConfig remediation available:

| Check | Type | Description |
|-------|------|-------------|
| `ocp4-cis-configure-network-policies-namespaces` | CIS | Ensure all application namespaces have NetworkPolicy defined |
| `ocp4-cis-rbac-least-privilege` | CIS | Review RBAC permissions for least privilege |

---

## MEDIUM Severity Remediations

### Group M1: SSHD Configuration (Medium)
**Severity**: MEDIUM
**File**: `75-sshd-hardening.yaml` (consolidated with H3, L1)
**Count**: 7 settings (master/worker)
**Status**: In Progress - [PR #466](https://github.com/openshift-kni/telco-reference/pull/466)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| PermitRootLogin | no | Disable direct root SSH access |
| GSSAPIAuthentication | no | Disable GSSAPI authentication |
| IgnoreRhosts | yes | Disable rhost authentication |
| IgnoreUserKnownHosts | yes | Ignore user's known_hosts file |
| PermitUserEnvironment | no | Block user environment variable passing |
| StrictModes | yes | Enable strict mode checking |
| PrintLastLog | yes | Display last login information |

**Source Files**:
- `medium/rhcos4-e8-worker-sshd-disable-root-login.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-gssapi-auth.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-rhosts.yaml`
- `medium/rhcos4-e8-worker-sshd-disable-user-known-hosts.yaml`
- `medium/rhcos4-e8-worker-sshd-do-not-permit-user-env.yaml`
- `medium/rhcos4-e8-worker-sshd-enable-strictmodes.yaml`
- `medium/rhcos4-e8-worker-sshd-print-last-log.yaml`

---

### Group M2: Kernel Hardening (Sysctl)
**Severity**: MEDIUM
**File**: `75-sysctl-medium.yaml`
**Count**: 4 settings (master/worker)
**Status**: On Hold - PR #528 closed (focusing on HIGH severity first)
**Jira**: [CNF-21196](https://issues.redhat.com/browse/CNF-21196)

| Setting | Value | Description |
|---------|-------|-------------|
| kernel.randomize_va_space | 2 | Full ASLR - randomizes memory layout |
| kernel.unprivileged_bpf_disabled | 1 | Prevent BPF-based privilege escalation |
| kernel.yama.ptrace_scope | 1 | Restrict ptrace to parent-child processes |
| net.core.bpf_jit_harden | 2 | Harden BPF JIT against spraying attacks |

**Source Files**:
- `medium/rhcos4-e8-worker-sysctl-kernel-randomize-va-space.yaml`
- `medium/rhcos4-e8-worker-sysctl-kernel-unprivileged-bpf-disabled.yaml`
- `medium/rhcos4-e8-worker-sysctl-kernel-yama-ptrace-scope.yaml`
- `medium/rhcos4-e8-worker-sysctl-net-core-bpf-jit-harden.yaml`

---

### Group M3: Audit Rules - DAC Modifications
**Severity**: MEDIUM
**File**: `75-audit-dac-medium.yaml`
**Count**: 2 settings (master/worker)

| Rule | Description |
|------|-------------|
| chmod | Audit file permission changes via chmod |
| chown | Audit file ownership changes via chown |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-dac-modification-chmod.yaml`
- `medium/rhcos4-e8-worker-audit-rules-dac-modification-chown.yaml`

---

### Group M4: Audit Rules - SELinux/Privilege Execution
**Severity**: MEDIUM
**File**: `75-audit-privilege-medium.yaml`
**Count**: 6 settings (master/worker)

| Rule | Description |
|------|-------------|
| chcon | Audit SELinux context changes |
| restorecon | Audit SELinux context restoration |
| semanage | Audit SELinux management commands |
| setfiles | Audit SELinux file labeling |
| setsebool | Audit SELinux boolean changes |
| seunshare | Audit SELinux unshare operations |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-execution-chcon.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-restorecon.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-semanage.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-setfiles.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-setsebool.yaml`
- `medium/rhcos4-e8-worker-audit-rules-execution-seunshare.yaml`

---

### Group M5: Audit Rules - Kernel Module Loading
**Severity**: MEDIUM
**File**: `75-audit-modules-medium.yaml`
**Count**: 3 settings (master/worker)

| Rule | Description |
|------|-------------|
| delete_module | Audit kernel module unloading (rmmod) |
| finit_module | Audit kernel module loading (finit) |
| init_module | Audit kernel module loading (init) |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-delete.yaml`
- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-finit.yaml`
- `medium/rhcos4-e8-worker-audit-rules-kernel-module-loading-init.yaml`

---

### Group M6: Audit Rules - Time Modifications
**Severity**: MEDIUM
**File**: `75-audit-time-medium.yaml`
**Count**: 5 settings (master/worker)

| Rule | Description |
|------|-------------|
| adjtimex | Audit fine-grained time adjustments |
| clock_settime | Audit clock setting operations |
| settimeofday | Audit time-of-day changes |
| stime | Audit legacy time setting |
| /etc/localtime | Watch for localtime file changes |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-time-adjtimex.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-clock-settime.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-settimeofday.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-stime.yaml`
- `medium/rhcos4-e8-worker-audit-rules-time-watch-localtime.yaml`

---

### Group M7: Audit Rules - Login/Auth Monitoring
**Severity**: MEDIUM
**File**: `75-audit-auth-medium.yaml`
**Count**: 5 settings (master/worker)

| Rule | Description |
|------|-------------|
| faillock | Monitor failed login attempts |
| lastlog | Monitor last login records |
| tallylog | Monitor login attempt tallies |
| sudoers | Monitor sudo configuration changes |
| usergroup | Monitor /etc/passwd, /etc/group, /etc/shadow changes |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-login-events-faillock.yaml`
- `medium/rhcos4-e8-worker-audit-rules-login-events-lastlog.yaml`
- `medium/rhcos4-e8-worker-audit-rules-login-events-tallylog.yaml`
- `medium/rhcos4-e8-worker-audit-rules-sysadmin-actions.yaml`
- `medium/rhcos4-e8-worker-audit-rules-usergroup-modification.yaml`

---

### Group M8: Audit Rules - Network Configuration
**Severity**: MEDIUM
**File**: `75-audit-network-medium.yaml`
**Count**: 1 setting (master/worker)

| Rule | Description |
|------|-------------|
| network_modification | Audit sethostname, setdomainname syscalls |

**Source Files**:
- `medium/rhcos4-e8-worker-audit-rules-networkconfig-modification.yaml`

---

### Group M9: Auditd Configuration
**Severity**: MEDIUM
**File**: `75-auditd-config-medium.yaml`
**Count**: 1 setting (master/worker)

| Setting | Value | Description |
|---------|-------|-------------|
| name_format | hostname | Log hostname in audit records |

**Source Files**:
- `medium/rhcos4-e8-worker-auditd-name-format.yaml`

---

### Group M10: API Server Encryption (CRD)
**Severity**: MEDIUM
**Type**: APIServer CRD
**File**: `75-api-server-encryption-medium.yaml`
**Count**: 2 remediations

| Setting | Value | Description |
|---------|-------|-------------|
| encryption.type | aescbc | Enable AES-CBC encryption at rest |

**Source Files**:
- `medium/ocp4-cis-api-server-encryption-provider-cipher.yaml`
- `medium/ocp4-e8-api-server-encryption-provider-cipher.yaml`

---

### Group M11: Ingress TLS Ciphers (CRD)
**Severity**: MEDIUM
**Type**: IngressController CRD
**File**: `75-ingress-tls-medium.yaml`
**Count**: 1 remediation

| Setting | Description |
|---------|-------------|
| tlsSecurityProfile | Custom TLS profile with specific cipher suites |

**Source Files**:
- `medium/ocp4-cis-ingress-controller-tls-cipher-suites.yaml`

---

### Group M12: Audit Profile (CRD)
**Severity**: MEDIUM
**Type**: APIServer CRD
**File**: `75-audit-profile-medium.yaml`
**Count**: 1 remediation

| Setting | Value | Description |
|---------|-------|-------------|
| audit.profile | WriteRequestBodies | Enhanced audit logging |

**Source Files**:
- `medium/ocp4-cis-audit-profile-set.yaml`

---

## LOW Severity Remediations

### Group L1: SSHD LogLevel
**Severity**: LOW
**File**: `75-sshd-hardening.yaml` (consolidated with H3, M1)
**Count**: 1 setting (master/worker)
**Status**: In Progress - [PR #466](https://github.com/openshift-kni/telco-reference/pull/466)
**Jira**: [CNF-19031](https://issues.redhat.com/browse/CNF-19031)

| Setting | Value | Description |
|---------|-------|-------------|
| LogLevel | INFO | Set SSH logging to INFO level |

**Source Files**:
- `low/rhcos4-e8-worker-sshd-set-loglevel-info.yaml`
- `low/rhcos4-e8-master-sshd-set-loglevel-info.yaml`

---

### Group L2: Sysctl dmesg_restrict
**Severity**: LOW
**File**: `75-sysctl-low.yaml`
**Count**: 1 setting (master/worker)

| Setting | Value | Description |
|---------|-------|-------------|
| kernel.dmesg_restrict | 1 | Restrict kernel log access to privileged users |

**Source Files**:
- `low/rhcos4-e8-worker-sysctl-kernel-dmesg-restrict.yaml`
- `low/rhcos4-e8-master-sysctl-kernel-dmesg-restrict.yaml`

---

## Summary Table

| Severity | Group | Category | Count | Type | Status | Jira | PR |
|----------|-------|----------|-------|------|--------|------|-----|
| HIGH | H1 | Crypto Policy | 1 | MachineConfig | In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| HIGH | H2 | PAM Empty Passwords | 1 | MachineConfig | In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| HIGH | H3 | SSHD Empty Passwords | 1 | MachineConfig | In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| HIGH | - | Network Policies | - | Manual | N/A | - | - |
| HIGH | - | RBAC Least Privilege | - | Manual | N/A | - | - |
| MEDIUM | M1 | SSHD Configuration | 7 | MachineConfig | In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| MEDIUM | M2 | Kernel Sysctl | 4 | MachineConfig | On Hold | [CNF-21196](https://issues.redhat.com/browse/CNF-21196) | PR #528 closed |
| MEDIUM | M3 | Audit DAC | 2 | MachineConfig | Pending | - | - |
| MEDIUM | M4 | Audit SELinux | 6 | MachineConfig | Pending | - | - |
| MEDIUM | M5 | Audit Modules | 3 | MachineConfig | Pending | - | - |
| MEDIUM | M6 | Audit Time | 5 | MachineConfig | Pending | - | - |
| MEDIUM | M7 | Audit Auth | 5 | MachineConfig | Pending | - | - |
| MEDIUM | M8 | Audit Network | 1 | MachineConfig | Pending | - | - |
| MEDIUM | M9 | Auditd Config | 1 | MachineConfig | Pending | - | - |
| MEDIUM | M10 | API Encryption | 2 | APIServer CRD | Pending | - | - |
| MEDIUM | M11 | Ingress TLS | 1 | IngressController CRD | Pending | - | - |
| MEDIUM | M12 | Audit Profile | 1 | APIServer CRD | Pending | - | - |
| LOW | L1 | SSHD LogLevel | 1 | MachineConfig | In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| LOW | L2 | Sysctl dmesg | 1 | MachineConfig | Pending | - | - |

---

## Jira Issues Tracking

| Severity | Count | Groups | Jira | Notes |
|----------|-------|--------|------|-------|
| HIGH | 3 | H1, H2, H3 | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | All auto-remediations covered |
| HIGH | 2 | Manual | N/A | Network Policies, RBAC (no auto-remediation) |
| MEDIUM | 12 | M1-M12 | Pending | M1: CNF-19031, M2: CNF-21196 (on hold) |
| LOW | 2 | L1, L2 | Pending | |
| **Total** | **19** | | | |

---

## Notes

- **Severity Source**: Severity levels come directly from Compliance Operator's ComplianceCheckResult objects
- **File Naming**: Use `75-<category>-<severity>.yaml` pattern (e.g., `75-sysctl-medium.yaml`)
- **SSHD Consolidation**: All SSHD settings (H3, M1, L1) consolidated into `75-sshd-hardening.yaml` in PR #466
- **PR #528 Closed**: Was named "high" but contained only MEDIUM severity sysctl settings - closed
- **PR #529**: Non-SSHD HIGH severity items (crypto-policy, PAM)
- **PR #466**: All SSHD hardening (HIGH + MEDIUM + LOW)
