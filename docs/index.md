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

## Scan History

<div style="max-width:800px;margin:1.5rem 0;">
  <canvas id="scan-trend-chart" aria-label="Compliance scan trend chart"></canvas>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.4/chart.umd.min.js"></script>
<script>
(function() {
  var scanHistory = {{ site.data.scan-history | jsonify }};
  var sorted = scanHistory.slice().sort(function(a, b) {
    return a.scan_date.localeCompare(b.scan_date);
  });
  var labels = sorted.map(function(r) {
    return 'OCP ' + r.version + ' (' + r.scan_date.slice(0, 10) + ')';
  });
  var ctx = document.getElementById('scan-trend-chart').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: labels,
      datasets: [
        {
          label: 'Passing',
          data: sorted.map(function(r) { return r.summary.passing; }),
          borderColor: '#2a9d44',
          backgroundColor: 'rgba(42,157,68,0.1)',
          tension: 0.3,
          fill: true
        },
        {
          label: 'Failing',
          data: sorted.map(function(r) { return r.summary.failing; }),
          borderColor: '#c00',
          backgroundColor: 'rgba(204,0,0,0.1)',
          tension: 0.3,
          fill: true
        },
        {
          label: 'Manual',
          data: sorted.map(function(r) { return r.summary.manual; }),
          borderColor: '#888',
          backgroundColor: 'rgba(136,136,136,0.1)',
          tension: 0.3,
          fill: false
        }
      ]
    },
    options: {
      responsive: true,
      plugins: {
        legend: { position: 'top' },
        tooltip: {
          callbacks: {
            afterBody: function(items) {
              var r = sorted[items[0].dataIndex];
              var lines = [];
              if (r.notes) lines.push('Note: ' + r.notes);
              if (r.profiles) {
                Object.keys(r.profiles).forEach(function(p) {
                  var pr = r.profiles[p];
                  lines.push(p + ': ' + pr.passing + ' pass / ' + pr.failing + ' fail');
                });
              }
              return lines;
            }
          }
        }
      },
      scales: {
        y: { beginAtZero: true, title: { display: true, text: 'Check Count' } }
      }
    }
  });
})();
</script>

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
