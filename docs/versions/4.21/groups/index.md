---
layout: default
title: OCP 4.21 Remediation Groups
---

# OCP 4.21 Remediation Groups

[← Back to OCP 4.21 Compliance Status](../4.21.html) | [View Summary](../remediations.html)

Each group below represents a logical set of related compliance checks that can be remediated together in a single MachineConfig or CRD.

<div class="filter-bar">
  <div class="filter-search">
    <input type="text" id="table-search" placeholder="Search groups..." onkeyup="filterTables()">
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
| [M1](M1.html) | SSHD Configuration | <span class="priority-score p2">P2</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:m1-sshd-medium-hardening) | - | - |
| [M4](M4.html) | Audit Rules - SELinux | <span class="priority-score p2">P2</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m4-audit-selinux) | - | - |
| [M6](M6.html) | Audit Rules - Time Modifications | <span class="priority-score p2">P2</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m6-audit-time) | - | - |
| [M7](M7.html) | Audit Rules - Login Monitoring | <span class="priority-score p2">P2</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m7-audit-login) | - | - |
| [M10](M10.html) | API Server Encryption | <span class="priority-score p2">P2</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m10-api-encryption) | - | - |
| [M2](M2.html) | Kernel Hardening (Sysctl) | <span class="priority-score p3">P3</span> | ⚪ On Hold | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m2-kernel-sysctl) | [CNF-21196](https://issues.redhat.com/browse/CNF-21196) | - |
| [M3](M3.html) | Audit Rules - DAC Modifications | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m3-audit-dac) | - | - |
| [M5](M5.html) | Audit Rules - Kernel Modules | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m5-audit-modules) | - | - |
| [M8](M8.html) | Audit Rules - Network Config | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m8-audit-network) | - | - |
| [M9](M9.html) | Auditd Configuration | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m9-auditd-config) | - | - |
| [M11](M11.html) | Ingress TLS Ciphers | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m11-ingress-tls) | - | - |
| [M12](M12.html) | Audit Profile | <span class="priority-score p3">P3</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/m12-audit-profile) | - | - |

---

## LOW Severity

| Group | Title | Priority | Status | Compare | Jira | PR |
|-------|-------|----------|--------|---------|------|-----|
| [L1](L1.html) | SSHD LogLevel | <span class="priority-score p4">P4</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/l1-sshd-loglevel) | - | - |
| [L2](L2.html) | Sysctl dmesg_restrict | <span class="priority-score p4">P4</span> | 🟡 Pending | [📦](https://github.com/openshift-kni/telco-reference/compare/main...sebrandon1:telco-reference:compliance/4.21/l2-sysctl-dmesg) | - | - |

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
      if (row.querySelector('th')) return; // Skip header rows
      totalCount++;
      var text = row.textContent.toLowerCase();
      var statusCell = row.cells[2] ? row.cells[2].textContent : '';

      var matchesSearch = searchTerm === '' || text.includes(searchTerm);
      var matchesFilter = currentFilter === 'all' ||
        (currentFilter === 'pending' && statusCell.includes('Pending')) ||
        (currentFilter === 'in_progress' && statusCell.includes('In Progress')) ||
        (currentFilter === 'on_hold' && statusCell.includes('On Hold')) ||
        (currentFilter === 'complete' && statusCell.includes('Complete'));

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
