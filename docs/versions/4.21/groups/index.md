---
layout: default
title: OCP 4.21 Remediation Groups
---

# OCP 4.21 Remediation Groups

[← Back to OCP 4.21 Compliance Status](../4.21.html) | [View Summary](../remediations.html)

Each group below represents a logical set of related compliance checks that can be remediated together in a single MachineConfig or CRD.

---

## HIGH Severity

| Group | Title | Status | Jira | PR |
|-------|-------|--------|------|-----|
| [H1](H1.html) | Crypto Policy | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H2](H2.html) | PAM Empty Passwords | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H3](H3.html) | SSHD Empty Passwords | 🔵 In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |

---

## MEDIUM Severity

| Group | Title | Status | Jira | PR |
|-------|-------|--------|------|-----|
| [M1](M1.html) | SSHD Configuration | 🔵 In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| [M2](M2.html) | Kernel Hardening (Sysctl) | ⚪ On Hold | [CNF-21196](https://issues.redhat.com/browse/CNF-21196) | - |
| [M3](M3.html) | Audit Rules - DAC Modifications | 🟡 Pending | - | - |
| [M4](M4.html) | Audit Rules - SELinux | 🟡 Pending | - | - |
| [M5](M5.html) | Audit Rules - Kernel Modules | 🟡 Pending | - | - |
| [M6](M6.html) | Audit Rules - Time Modifications | 🟡 Pending | - | - |
| [M7](M7.html) | Audit Rules - Login Monitoring | 🟡 Pending | - | - |
| [M8](M8.html) | Audit Rules - Network Config | 🟡 Pending | - | - |
| [M9](M9.html) | Auditd Configuration | 🟡 Pending | - | - |
| [M10](M10.html) | API Server Encryption | 🟡 Pending | - | - |
| [M11](M11.html) | Ingress TLS Ciphers | 🟡 Pending | - | - |
| [M12](M12.html) | Audit Profile | 🟡 Pending | - | - |

---

## LOW Severity

| Group | Title | Status | Jira | PR |
|-------|-------|--------|------|-----|
| [L1](L1.html) | SSHD LogLevel | 🔵 In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |
| [L2](L2.html) | Sysctl dmesg_restrict | 🟡 Pending | - | - |

---

## Group Naming Convention

- **H** = HIGH severity (H1, H2, H3)
- **M** = MEDIUM severity (M1-M12)
- **L** = LOW severity (L1, L2)

## Status Legend

| Status | Meaning |
|--------|---------|
| 🔵 In Progress | Active PR open for remediation |
| 🟡 Pending | Not yet started |
| ⚪ On Hold | Paused |
| 🟢 Complete | Merged and verified |

---

## Linking to Groups from PRs

Use these URLs in your PR descriptions:

```
https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H1.html
https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/M1.html
```

Example markdown for PR descriptions:
```markdown
This PR implements [H1: Crypto Policy](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H1.html)
and [H2: PAM Empty Passwords](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H2.html).
```
