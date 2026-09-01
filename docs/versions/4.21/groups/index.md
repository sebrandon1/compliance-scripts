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
  <div class="filter-buttons">
    <button class="filter-btn upstream-filter active" data-upstream="all" onclick="setUpstreamFilter('all')">All Upstream</button>
    <button class="filter-btn upstream-filter" data-upstream="upstream-candidate" onclick="setUpstreamFilter('upstream-candidate')">🔼 Candidate</button>
    <button class="filter-btn upstream-filter" data-upstream="ran-only" onclick="setUpstreamFilter('ran-only')">🎯 RAN Only</button>
    <button class="filter-btn upstream-filter" data-upstream="platform-config" onclick="setUpstreamFilter('platform-config')">⚙️ Platform</button>
    <button class="filter-btn upstream-filter" data-upstream="pass-vanilla" onclick="setUpstreamFilter('pass-vanilla')">✅ Pass</button>
    <button class="filter-btn upstream-filter" data-upstream="not-applicable" onclick="setUpstreamFilter('not-applicable')">— N/A</button>
    <button class="filter-btn upstream-filter" data-upstream="has-branch" onclick="setUpstreamFilter('has-branch')">🔧 Branch Prepared</button>
  </div>
  <div class="filter-counts" id="filter-counts"></div>
</div>

{% include resolve-tracking.html %}
{% assign groups = tracking.groups %}
{% assign meta = tracking.meta %}
{% assign high_order = "H1,H2,H3" | split: "," %}
{% assign medium_order = "M1,M2,M3,M4,M5,M6,M7,M8,M9,M10,M11,M12,M13,M14,M15,M16,M17,M18,M19,M20,M21,M22,M23,M24,M25,M26,M27,M28,M29,M30" | split: "," %}
{% assign low_order = "L1,L2" | split: "," %}
{% assign manual_order = "MAN1,MAN2,MAN3,MAN4,MAN5" | split: "," %}

---

## HIGH Severity

| Group | Title | Priority | Status | Jira | PR |
|-------|-------|----------|--------|------|-----|
{% for gid in high_order %}{% assign g = groups[gid] %}{% if g %}| [{{ gid }}]({{ gid }}.html) | {{ g.title }} | <span class="priority-score p{{ g.priority }}">P{{ g.priority }}</span> | {% if g.status == "verified" %}🟢 Verified{% elsif g.status == "in_progress" %}🔵 In Progress{% elsif g.status == "pending" %}🟡 Pending{% elsif g.status == "on_hold" %}⚪ On Hold{% elsif g.status == "partial" %}🟠 Partial{% elsif g.status contains "pass-vanilla" %}✅ PASS (vanilla){% else %}{{ g.status }}{% endif %} | {% if g.jira %}[{{ g.jira }}]({{ meta.jira_base_url }}{{ g.jira }}){% else %}-{% endif %} | {% if g.pr %}[#{{ g.pr }}]({{ meta.pr_base_url }}{{ g.pr }}){% else %}-{% endif %} |
{% endif %}{% endfor %}

---

## MEDIUM Severity

| Group | Title | Priority | Status | Compare | Jira | PR |
|-------|-------|----------|--------|---------|------|-----|
{% for gid in medium_order %}{% assign g = groups[gid] %}{% if g %}| [{{ gid }}]({{ gid }}.html) | {{ g.title }} | <span class="priority-score p{{ g.priority }}">P{{ g.priority }}</span> | {% if g.status == "verified" %}🟢 Verified{% elsif g.status == "in_progress" %}🔵 In Progress{% elsif g.status == "pending" %}🟡 Pending{% elsif g.status == "on_hold" %}⚪ On Hold{% elsif g.status == "partial" %}🟠 Partial{% elsif g.status contains "pass-vanilla" %}✅ PASS (vanilla){% else %}{{ g.status }}{% endif %} | {% if g.compare %}[📦]({{ meta.compare_base_url }}{{ g.compare }}){% else %}-{% endif %} | {% if g.jira %}[{{ g.jira }}]({{ meta.jira_base_url }}{{ g.jira }}){% else %}-{% endif %} | {% if g.pr %}[#{{ g.pr }}]({{ meta.pr_base_url }}{{ g.pr }}){% else %}-{% endif %} |
{% endif %}{% endfor %}

---

## LOW Severity

| Group | Title | Priority | Status | Compare | Jira | PR |
|-------|-------|----------|--------|---------|------|-----|
{% for gid in low_order %}{% assign g = groups[gid] %}{% if g %}| [{{ gid }}]({{ gid }}.html) | {{ g.title }} | <span class="priority-score p{{ g.priority }}">P{{ g.priority }}</span> | {% if g.status == "verified" %}🟢 Verified{% elsif g.status == "in_progress" %}🔵 In Progress{% elsif g.status == "pending" %}🟡 Pending{% elsif g.status == "on_hold" %}⚪ On Hold{% elsif g.status == "partial" %}🟠 Partial{% elsif g.status contains "pass-vanilla" %}✅ PASS (vanilla){% else %}{{ g.status }}{% endif %} | {% if g.compare %}[📦]({{ meta.compare_base_url }}{{ g.compare }}){% else %}-{% endif %} | {% if g.jira %}[{{ g.jira }}]({{ meta.jira_base_url }}{{ g.jira }}){% else %}-{% endif %} | {% if g.pr %}[#{{ g.pr }}]({{ meta.pr_base_url }}{{ g.pr }}){% else %}-{% endif %} |
{% endif %}{% endfor %}

---

## Manual Checks (No Auto-Remediation)

These checks require manual operator review — no MachineConfig or CRD can fix them automatically.

| Group | Title | Priority | Status |
|-------|-------|----------|--------|
{% for gid in manual_order %}{% assign g = groups[gid] %}{% if g %}| [{{ gid }}]({{ gid }}.html) | {{ g.title }} | <span class="priority-score p{{ g.priority }}">P{{ g.priority }}</span> | {% if g.status == "verified" %}🟢 Verified{% elsif g.status == "in_progress" %}🔵 In Progress{% elsif g.status == "pending" %}🟡 Pending{% elsif g.status == "on_hold" %}⚪ On Hold{% elsif g.status == "partial" %}🟠 Partial{% elsif g.status contains "pass-vanilla" %}✅ PASS (vanilla){% else %}{{ g.status }}{% endif %} |
{% endif %}{% endfor %}

---

## Group Naming Convention

- **H** = HIGH severity (H1, H2, H3)
- **M** = MEDIUM severity (M1-M30)
- **L** = LOW severity (L1, L2)
- **MAN** = Manual checks (MAN1-MAN5)

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
