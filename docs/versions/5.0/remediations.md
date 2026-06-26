---
title: OCP 5.0 Remediation Groupings
version: "5.0"
---

# OCP 5.0 Remediation Groupings

[← Back to OCP 5.0 Compliance Status](../5.0.html) | [View Detailed Group Pages](groups/)

This page catalogs all compliance remediation groups for **OCP 5.0**, dynamically generated from tracking data.

> **Target baseline**: RHCOS 10.2 (OCP 5.0) with compliance-operator and pinned content image.

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
  <div class="filter-buttons">
    <button class="filter-btn platform-filter active" data-platform="all" onclick="setPlatformFilter('all')">All Platforms</button>
    <button class="filter-btn platform-filter" data-platform="rhcos" onclick="setPlatformFilter('rhcos')">RHCOS</button>
    <button class="filter-btn platform-filter" data-platform="ocp" onclick="setPlatformFilter('ocp')">OCP</button>
    <button class="filter-btn platform-filter" data-platform="mixed" onclick="setPlatformFilter('mixed')">Mixed</button>
  </div>
  <div class="filter-buttons">
    <button class="filter-btn upstream-filter active" data-upstream="all" onclick="setUpstreamFilter('all')">All Upstream</button>
    <button class="filter-btn upstream-filter" data-upstream="upstream-candidate" onclick="setUpstreamFilter('upstream-candidate')">🔼 Candidate</button>
    <button class="filter-btn upstream-filter" data-upstream="ran-only" onclick="setUpstreamFilter('ran-only')">🎯 RAN Only</button>
    <button class="filter-btn upstream-filter" data-upstream="platform-config" onclick="setUpstreamFilter('platform-config')">⚙️ Platform</button>
    <button class="filter-btn upstream-filter" data-upstream="not-applicable" onclick="setUpstreamFilter('not-applicable')">— N/A</button>
    <button class="filter-btn upstream-filter" data-upstream="has-branch" onclick="setUpstreamFilter('has-branch')">🔧 Branch Prepared</button>
  </div>
  <div class="filter-counts" id="filter-counts"></div>
</div>

## Quick Summary

{% include resolve-tracking.html %}
{% assign groups = tracking.groups %}
{% assign remediations = tracking.remediations %}
{% assign meta = tracking.meta %}

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
| ✅ PASS on vanilla RHCOS 10.2+ | {{ pass_vanilla_count }} groups |
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
      <th style="width: 90px;">Platform</th>
      <th style="width: 80px;">Severity</th>
      <th style="width: 50px; text-align: center;">Checks</th>
      <th style="width: 160px;">Status</th>
      <th style="width: 120px;">Upstream</th>
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
    {% assign has_branch = false %}{% if g.upstream %}{% for u in g.upstream %}{% if u.compare_url %}{% assign has_branch = true %}{% endif %}{% endfor %}{% endif %}
    <tr data-status="{{ g.status }}" data-platform="{{ g.platform }}" data-upstream="{{ g.upstream_verdict }}" data-has-branch="{{ has_branch }}">
      <td><a href="groups/{{ gid }}.html" class="group-id">{{ gid }}</a></td>
      <td>{{ g.title }}</td>
      <td>
        {% if g.platform %}
        <span class="platform-badge {{ g.platform }}">
          {% if g.platform == "rhcos" %}RHCOS
          {% elsif g.platform == "ocp" %}OCP
          {% elsif g.platform == "mixed" %}Mixed
          {% endif %}
        </span>
        {% else %}-{% endif %}
      </td>
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
      <td>
        {% if g.upstream_verdict == "upstream-candidate" %}
          <span class="upstream-badge candidate">🔼 Candidate</span>
        {% elsif g.upstream_verdict contains "upstream-pr" %}
          <span class="upstream-badge pr-exists">🟣 PR Open</span>
        {% elsif g.upstream_verdict == "ran-only" %}
          <span class="upstream-badge ran-only">🎯 RAN Only</span>
        {% elsif g.upstream_verdict == "platform-config" %}
          <span class="upstream-badge platform">⚙️ Platform</span>
        {% elsif g.upstream_verdict == "pass-vanilla" %}
          <span class="upstream-badge pass">✅ Pass</span>
        {% elsif g.upstream_verdict == "site-specific" %}
          <span class="upstream-badge site">📍 Site</span>
        {% elsif g.upstream_verdict == "not-applicable" %}
          <span class="upstream-badge na">— N/A</span>
        {% else %}
          <span class="upstream-badge">—</span>
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
          <a href="{{ meta.pr_base_url }}{{ g.pr }}" class="pr-badge{% if g.pr_state == 'merged' %} merged{% endif %}">#{{ g.pr }}{% if g.pr_state == "merged" %} ✓{% endif %}</a>
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
{% if g.status contains "pass-vanilla" %}✅ PASS (vanilla RHCOS 10.2+)
{% elsif g.status == "verified" %}🟢 Verified
{% elsif g.status == "in_progress" %}🔵 In Progress
{% elsif g.status == "pending" %}🟡 Pending
{% elsif g.status == "partial" %}🟠 Partial
{% else %}{{ g.status }}{% endif %}
{% if g.pr %} — <a href="{{ meta.pr_base_url }}{{ g.pr }}">PR #{{ g.pr }}{% if g.pr_state == "merged" %} (merged){% endif %}</a>{% endif %}
</summary>

{% if g.status contains "pass-vanilla" %}
> These checks PASS on vanilla RHCOS 10.2+ (OCP 5.0+) without MachineConfig remediation.
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
function updateHash() {
  var params = [];
  if (currentFilter !== 'all') params.push('status=' + currentFilter);
  if (currentPlatform !== 'all') params.push('platform=' + currentPlatform);
  if (currentUpstream !== 'all') params.push('upstream=' + currentUpstream);
  var search = (document.getElementById('table-search').value || '');
  if (search) params.push('q=' + encodeURIComponent(search));
  history.replaceState(null, '', params.length ? '#' + params.join('&') : location.pathname);
}
function parseHash() {
  var hash = location.hash.slice(1);
  if (!hash) return {};
  var result = {};
  hash.split('&').forEach(function(part) {
    var idx = part.indexOf('=');
    if (idx === -1) return;
    result[part.slice(0, idx)] = decodeURIComponent(part.slice(idx + 1));
  });
  return result;
}
var currentFilter = 'all';
var currentPlatform = 'all';
var currentUpstream = 'all';
function setStatusFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-btn:not(.platform-filter):not(.upstream-filter)').forEach(b => b.classList.remove('active'));
  document.querySelector('[data-filter="' + filter + '"]').classList.add('active');
  filterTables();
}
function setPlatformFilter(platform) {
  currentPlatform = platform;
  document.querySelectorAll('.platform-filter').forEach(b => b.classList.remove('active'));
  document.querySelector('[data-platform="' + platform + '"]').classList.add('active');
  filterTables();
}
function setUpstreamFilter(upstream) {
  currentUpstream = upstream;
  document.querySelectorAll('.upstream-filter').forEach(b => b.classList.remove('active'));
  document.querySelector('[data-upstream="' + upstream + '"]').classList.add('active');
  filterTables();
}
function filterTables() {
  var search = (document.getElementById('table-search').value || '').toLowerCase();
  var rows = document.querySelectorAll('#remediation-table tbody tr');
  var shown = 0, total = rows.length;
  rows.forEach(function(row) {
    var status = row.getAttribute('data-status') || '';
    var platform = row.getAttribute('data-platform') || '';
    var upstream = row.getAttribute('data-upstream') || '';
    var text = row.textContent.toLowerCase();
    var matchSearch = !search || text.indexOf(search) !== -1;
    var matchFilter = currentFilter === 'all' ||
      (currentFilter === 'pass-vanilla' && status.indexOf('pass-vanilla') !== -1) ||
      (currentFilter !== 'pass-vanilla' && status === currentFilter);
    var matchPlatform = currentPlatform === 'all' || platform === currentPlatform;
    var hasBranch = row.getAttribute('data-has-branch') === 'true';
    var matchUpstream = currentUpstream === 'all' || upstream === currentUpstream ||
      (currentUpstream === 'has-branch' && hasBranch);
    row.style.display = (matchSearch && matchFilter && matchPlatform && matchUpstream) ? '' : 'none';
    if (matchSearch && matchFilter && matchPlatform && matchUpstream) shown++;
  });
  document.getElementById('filter-counts').textContent = shown + ' of ' + total + ' groups';
  updateHash();
}
(function restoreFromHash() {
  var h = parseHash();
  if (h.status) setStatusFilter(h.status);
  if (h.platform) setPlatformFilter(h.platform);
  if (h.upstream) setUpstreamFilter(h.upstream);
  if (h.q) {
    document.getElementById('table-search').value = h.q;
  }
  filterTables();
})();
</script>
