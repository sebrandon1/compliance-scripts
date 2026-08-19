---
layout: default
title: OCP 4.21 Remediation Groups
version: "4.21"
---

# OCP 4.21 Remediation Groups

[← Back to OCP 4.21 Compliance Status](../../4.21.html) | [View Summary](../remediations.html)

Each group below represents a logical set of related compliance checks that can be remediated together in a single MachineConfig or CRD.

<div class="filter-bar">
  <div class="filter-search">
    <input type="text" id="table-search" placeholder="Search groups..." onkeyup="filterTables()">
  </div>
  {% include status-filter-buttons.html %}
  <div class="filter-counts" id="filter-counts"></div>
</div>

---

## HIGH Severity

| Group | Title | Priority | Status | Jira | PR |
|-------|-------|----------|--------|------|-----|
| [H1](H1.html) | Crypto Policy | <span class="priority-score p1">P1</span> | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H2](H2.html) | PAM Empty Passwords | <span class="priority-score p1">P1</span> | 🔵 In Progress | [CNF-21212](https://issues.redhat.com/browse/CNF-21212) | [#529](https://github.com/openshift-kni/telco-reference/pull/529) |
| [H3](H3.html) | SSHD Empty Passwords | <span class="priority-score p1">P1</span> | 🔵 In Progress | [CNF-19031](https://issues.redhat.com/browse/CNF-19031) | [#466](https://github.com/openshift-kni/telco-reference/pull/466) |

---

## MEDIUM Severity

| Group | Title | Priority | Status | Compare | Jira | PR |
|-------|-------|----------|--------|---------|------|-----|
| [M1](M1.html) | SSHD Configuration | <span class="priority-score p2">P2</span> | 🟡 Pending | - | - | - |
| [M4](M4.html) | Audit Rules - SELinux | <span class="priority-score p2">P2</span> | 🟡 Pending | - | - | - |
| [M6](M6.html) | Audit Rules - Time Modifications | <span class="priority-score p2">P2</span> | 🟡 Pending | - | - | - |
| [M7](M7.html) | Audit Rules - Login Monitoring | <span class="priority-score p2">P2</span> | 🟡 Pending | - | - | - |
| [M10](M10.html) | API Server Encryption | <span class="priority-score p2">P2</span> | 🟡 Pending | - | - | - |
| [M2](M2.html) | Kernel Hardening (Sysctl) | <span class="priority-score p3">P3</span> | ⚪ On Hold | - | [CNF-21196](https://issues.redhat.com/browse/CNF-21196) | - |
| [M3](M3.html) | Audit Rules - DAC Modifications | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |
| [M5](M5.html) | Audit Rules - Kernel Modules | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |
| [M8](M8.html) | Audit Rules - Network Config | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |
| [M9](M9.html) | Auditd Configuration | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |
| [M11](M11.html) | Ingress TLS Ciphers | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |
| [M12](M12.html) | Audit Profile | <span class="priority-score p3">P3</span> | 🟡 Pending | - | - | - |

---

## LOW Severity

| Group | Title | Priority | Status | Compare | Jira | PR |
|-------|-------|----------|--------|---------|------|-----|
| [L1](L1.html) | SSHD LogLevel | <span class="priority-score p4">P4</span> | 🟡 Pending | - | - | - |
| [L2](L2.html) | Sysctl dmesg_restrict | <span class="priority-score p4">P4</span> | 🟡 Pending | - | - | - |

---

## Group Naming Convention

- **H** = HIGH severity (H1, H2, H3)
- **M** = MEDIUM severity (M1-M12)
- **L** = LOW severity (L1, L2)

## Priority Legend

| Priority | Label | Criteria |
|----------|-------|----------|
| <span class="priority-score p1">P1</span> | Critical | HIGH severity - security critical |
| <span class="priority-score p2">P2</span> | High | MEDIUM severity with high impact (5+ checks) or API/encryption |
| <span class="priority-score p3">P3</span> | Medium | MEDIUM severity with standard impact |
| <span class="priority-score p4">P4</span> | Low | LOW severity - best practices |
| <span class="priority-score p5">P5</span> | Deferred | On hold or blocked |

{% include status-legend.md %}

---

## Linking to Groups from PRs

Use these URLs in your PR descriptions:

<div class="copy-box">
  <code id="url-h1">https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H1.html</code>
  <button class="copy-btn" onclick="copyToClipboard('url-h1')" title="Copy to clipboard">📋</button>
</div>
<div class="copy-box">
  <code id="url-m1">https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/M1.html</code>
  <button class="copy-btn" onclick="copyToClipboard('url-m1')" title="Copy to clipboard">📋</button>
</div>

Example markdown for PR descriptions:
<div class="copy-box">
  <code id="example-md">This PR implements [H1: Crypto Policy](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H1.html) and [H2: PAM Empty Passwords](https://sebrandon1.github.io/compliance-scripts/versions/4.21/groups/H2.html).</code>
  <button class="copy-btn" onclick="copyToClipboard('example-md')" title="Copy to clipboard">📋</button>
</div>

<script src="{{ '/assets/js/status-filter.js' | relative_url }}"></script>
<script>
{% include resolve-tracking.html %}
{% include group-statuses-js.html %}
</script>
<script src="{{ '/assets/js/group-index-filters.js' | relative_url }}"></script>
<script>
function copyToClipboard(elementId) {
  var text = document.getElementById(elementId).textContent;
  navigator.clipboard.writeText(text).then(function() {
    var btn = event.target;
    var original = btn.textContent;
    btn.textContent = '✓';
    btn.classList.add('copied');
    setTimeout(function() {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 1500);
  });
}
</script>
