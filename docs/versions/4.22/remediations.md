---
title: OCP 4.22 Remediation Groupings
---

# OCP 4.22 Remediation Groupings

[← Back to OCP 4.22 Compliance Status](../4.22.html) | [View Detailed Group Pages](groups/)

This page catalogs all compliance remediation groups for **OCP 4.22**, dynamically generated from [tracking.json](https://github.com/sebrandon1/compliance-scripts/blob/main/docs/_data/tracking.json).

> **Target baseline**: RHCOS 9.8 (OCP 4.22) with compliance-operator v1.8.2 and pinned content [quay.io/bapalm/k8scontent:v0.1.80](https://quay.io/repository/bapalm/k8scontent).

<div class="filter-bar">
  <div class="filter-search">
    <input type="text" id="table-search" placeholder="Search remediations..." onkeyup="filterTables()">
  </div>
  <div class="filter-buttons">
    <button class="filter-btn active" data-filter="all" onclick="setStatusFilter('all')">All</button>
    <button class="filter-btn" data-filter="pass-vanilla" onclick="setStatusFilter('pass-vanilla')">✅ PASS (vanilla)</button>
    <button class="filter-btn" data-filter="verified" onclick="setStatusFilter('verified')">🟢 Verified</button>
    <button class="filter-btn" data-filter="in_progress" onclick="setStatusFilter('in_progress')">🔵 In Progress</button>
    <button class="filter-btn" data-filter="pending" onclick="setStatusFilter('pending')">🟡 Pending</button>
    <button class="filter-btn" data-filter="partial" onclick="setStatusFilter('partial')">🟠 Partial</button>
  </div>
  <div class="filter-counts" id="filter-counts"></div>
</div>

## Quick Summary

{% assign groups = site.data.tracking.groups %}
{% assign remediations = site.data.tracking.remediations %}
{% assign meta = site.data.tracking.meta %}

{% assign pass_vanilla_count = 0 %}
{% assign verified_count = 0 %}
{% assign in_progress_count = 0 %}
{% assign pending_count = 0 %}
{% assign partial_count = 0 %}
{% assign manual_count = 0 %}

{% for group in groups %}
  {% if group[1].status contains "pass-vanilla" %}
    {% assign pass_vanilla_count = pass_vanilla_count | plus: 1 %}
  {% elsif group[1].status == "verified" %}
    {% assign verified_count = verified_count | plus: 1 %}
  {% elsif group[1].status == "in_progress" %}
    {% assign in_progress_count = in_progress_count | plus: 1 %}
  {% elsif group[1].status == "pending" %}
    {% assign pending_count = pending_count | plus: 1 %}
  {% elsif group[1].status == "partial" %}
    {% assign partial_count = partial_count | plus: 1 %}
  {% endif %}
  {% if group[0] contains "MAN" %}
    {% assign manual_count = manual_count | plus: 1 %}
  {% endif %}
{% endfor %}

| Status | Count |
|--------|-------|
| ✅ PASS on vanilla RHCOS 9.8+ | {{ pass_vanilla_count }} groups |
| 🟢 Verified (remediation works) | {{ verified_count }} groups |
| 🔵 In Progress | {{ in_progress_count }} groups |
| 🟡 Pending | {{ pending_count }} groups |
| 🟠 Partial | {{ partial_count }} groups |
| 📋 Manual | {{ manual_count }} groups |

---

## Remediation Status

<table class="status-table" id="remediation-table">
  <thead>
    <tr>
      <th style="width: 60px;">Group</th>
      <th>Category</th>
      <th style="width: 80px;">Severity</th>
      <th style="width: 50px; text-align: center;">Checks</th>
      <th style="width: 160px;">Status</th>
      <th style="width: 50px; text-align: center;">Compare</th>
      <th style="width: 100px;">Jira</th>
      <th style="width: 70px;">PR</th>
    </tr>
  </thead>
  <tbody>
    {% for group in groups %}
    {% assign gid = group[0] %}
    {% assign g = group[1] %}
    {% assign check_count = 0 %}
    {% for rem in remediations %}
      {% if rem[1].group == gid %}
        {% assign check_count = check_count | plus: 1 %}
      {% endif %}
    {% endfor %}
    <tr data-status="{{ g.status }}">
      <td><a href="groups/{{ gid }}.html" class="group-id">{{ gid }}</a></td>
      <td>{{ g.title }}</td>
      <td><span class="severity-pill {{ g.severity | downcase }}">{{ g.severity }}</span></td>
      <td style="text-align: center;">{{ check_count }}</td>
      <td>
        {% if g.status contains "pass-vanilla" %}
          <span class="status-pill pass-vanilla">✅ PASS (vanilla)</span>
        {% elsif g.status == "verified" %}
          <span class="status-pill verified">🟢 Verified</span>
        {% elsif g.status == "in_progress" %}
          <span class="status-pill in-progress">🔵 In Progress</span>
        {% elsif g.status == "pending" %}
          <span class="status-pill pending">🟡 Pending</span>
        {% elsif g.status == "partial" %}
          <span class="status-pill partial">🟠 Partial</span>
        {% elsif g.status == "on_hold" %}
          <span class="status-pill on-hold">⚪ On Hold</span>
        {% else %}
          <span class="status-pill">{{ g.status }}</span>
        {% endif %}
      </td>
      <td style="text-align: center;">
        {% if g.compare %}
          <a href="{{ meta.compare_base_url }}{{ g.compare }}" class="compare-btn">📦</a>
        {% else %}-{% endif %}
      </td>
      <td>
        {% if g.jira %}
          <a href="{{ meta.jira_base_url }}{{ g.jira }}" class="jira-badge">{{ g.jira }}</a>
        {% else %}-{% endif %}
      </td>
      <td>
        {% if g.pr %}
          <a href="{{ meta.pr_base_url }}{{ g.pr }}" class="pr-badge">#{{ g.pr }}</a>
        {% else %}-{% endif %}
      </td>
    </tr>
    {% endfor %}
  </tbody>
</table>

---

## Remediation Details

{% for group in groups %}
{% assign gid = group[0] %}
{% assign g = group[1] %}
{% assign group_rems = "" %}

<details markdown="1"{% unless g.status contains "pass-vanilla" %} open{% endunless %}>
<summary><strong>{{ gid }}: {{ g.title }}</strong> —
{% if g.status contains "pass-vanilla" %}✅ PASS (vanilla RHCOS 9.8+)
{% elsif g.status == "verified" %}🟢 Verified
{% elsif g.status == "in_progress" %}🔵 In Progress
{% elsif g.status == "pending" %}🟡 Pending
{% elsif g.status == "partial" %}🟠 Partial
{% else %}{{ g.status }}{% endif %}
{% if g.pr %} — <a href="{{ meta.pr_base_url }}{{ g.pr }}">PR #{{ g.pr }}</a>{% endif %}
</summary>

{% if g.status contains "pass-vanilla" %}
> These checks PASS on vanilla RHCOS 9.8+ (OCP 4.22+) without MachineConfig remediation.
{% endif %}

{% if g.jira %}**Jira**: [{{ g.jira }}]({{ meta.jira_base_url }}{{ g.jira }}){% endif %}

| Check | Description |
|-------|-------------|
{% for rem in remediations %}{% if rem[1].group == gid %}| `{{ rem[0] }}` | {{ rem[1].description }} |
{% endif %}{% endfor %}

{% if g.status_note %}
*{{ g.status_note }}*
{% endif %}

</details>

{% endfor %}

---

## Legend

- **H** = HIGH severity (H1–H3)
- **M** = MEDIUM severity (M1–M30)
- **L** = LOW severity (L1, L2)
- **MAN** = Manual checks (MAN1–MAN5)

<script>
var currentFilter = 'all';
function setStatusFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
  document.querySelector('[data-filter="' + filter + '"]').classList.add('active');
  filterTables();
}
function filterTables() {
  var search = (document.getElementById('table-search').value || '').toLowerCase();
  var rows = document.querySelectorAll('#remediation-table tbody tr');
  var shown = 0, total = rows.length;
  rows.forEach(function(row) {
    var status = row.getAttribute('data-status') || '';
    var text = row.textContent.toLowerCase();
    var matchSearch = !search || text.indexOf(search) !== -1;
    var matchFilter = currentFilter === 'all' ||
      (currentFilter === 'pass-vanilla' && status.indexOf('pass-vanilla') !== -1) ||
      (currentFilter !== 'pass-vanilla' && status === currentFilter);
    row.style.display = (matchSearch && matchFilter) ? '' : 'none';
    if (matchSearch && matchFilter) shown++;
  });
  document.getElementById('filter-counts').textContent = shown + ' of ' + total + ' groups';
}
filterTables();
</script>
