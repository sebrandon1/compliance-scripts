---
layout: default
title: Compliance Remediation Tracker
---

# Compliance Remediation Tracker

Track OpenShift Compliance Operator results across OCP versions. This dashboard shows failing checks by severity level and links to Jira tickets and PRs for remediation.

## Tracked OCP Versions

<div class="version-list">
{% assign versions = site.pages | where_exp: "page", "page.layout == 'version'" | sort: "version" | reverse %}
{% for version_page in versions %}
  {% assign version_slug = version_page.version | replace: ".", "_" %}
  {% assign data_file = "ocp-" | append: version_slug %}
  {% assign version_data = site.data[data_file] %}
  <div class="version-card">
    <h3><a href="{{ version_page.url | relative_url }}">OCP {{ version_page.version }}</a></h3>
    {% if version_data %}
    <div class="stats">
      <div class="stat">
        <span class="stat-value pass">{{ version_data.summary.passing }}</span>
        <span class="stat-label">Passing</span>
      </div>
      <div class="stat">
        <span class="stat-value fail">{{ version_data.summary.failing }}</span>
        <span class="stat-label">Failing</span>
      </div>
    </div>
    {% include resolve-tracking.html version=version_page.version %}
    {% assign in_progress_count = 0 %}
    {% assign pending_count = 0 %}
    {% assign on_hold_count = 0 %}
    {% assign partial_count = 0 %}
    {% assign complete_count = 0 %}
    {% for g in tracking.groups %}
      {% if g[1].status == "in_progress" %}
        {% assign in_progress_count = in_progress_count | plus: 1 %}
      {% elsif g[1].status == "pending" %}
        {% assign pending_count = pending_count | plus: 1 %}
      {% elsif g[1].status == "on_hold" %}
        {% assign on_hold_count = on_hold_count | plus: 1 %}
      {% elsif g[1].status == "partial" %}
        {% assign partial_count = partial_count | plus: 1 %}
      {% elsif g[1].status == "verified" or g[1].status contains "pass-vanilla" %}
        {% assign complete_count = complete_count | plus: 1 %}
      {% endif %}
    {% endfor %}
    <p class="status-breakdown">
      <span title="In Progress">🔵 {{ in_progress_count }}</span>
      <span title="Pending">🟡 {{ pending_count }}</span>
      <span title="On Hold">⚪ {{ on_hold_count }}</span>
      {% if partial_count > 0 %}<span title="Partial">🟠 {{ partial_count }}</span>{% endif %}
      <span title="Complete">🟢 {{ complete_count }}</span>
    </p>
    <p><small>Last scan: {{ version_data.scan_date | date: "%Y-%m-%d" }}</small></p>
    {% else %}
    <p class="no-data"><small>No data yet. Run <code>make export-compliance OCP_VERSION={{ version_page.version }}</code></small></p>
    {% endif %}
    <a href="{{ version_page.url | relative_url }}">View Details &rarr;</a>
  </div>
{% endfor %}
</div>

{% if versions.size == 0 %}
<div class="no-data">
  <p>No OCP versions configured yet.</p>
  <p>Create version pages in <code>docs/versions/</code> to get started.</p>
</div>
{% endif %}

## Quick Links

- [Remediation Groupings]({{ '/REMEDIATION_GROUPINGS' | relative_url }}) - Grouped remediations by category
- [Compare]({{ '/compare' | relative_url }}) - Diff check results between OCP versions
- [Hardened]({{ '/hardened' | relative_url }}) - Scan history and group status across versions
- [GitHub Repository](https://github.com/sebrandon1/compliance-scripts) - Source code and scripts
- [Telco Reference PRs](https://github.com/openshift-kni/telco-reference/pulls) - Open remediation PRs

## How It Works

1. **Collect Data**: Run `make export-compliance OCP_VERSION=X.XX` against a cluster with Compliance Operator results
2. **Review Dashboard**: Check this page to see failing checks organized by severity
3. **Track Progress**: Update `_data/tracking.json` with Jira tickets and PR numbers
4. **Auto Deploy**: Push changes to main branch and GitHub Actions rebuilds the site

## Severity Levels

<span class="severity-badge high">HIGH</span> Critical security issues requiring immediate attention

<span class="severity-badge medium">MEDIUM</span> Important security hardening recommendations

<span class="severity-badge low">LOW</span> Best practice recommendations

<span class="severity-badge manual">MANUAL</span> Checks requiring manual review (cannot be auto-remediated)
