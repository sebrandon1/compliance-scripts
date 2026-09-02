---
layout: default
title: Compare Versions
---

<div class="version-page">
  <nav class="breadcrumb">
    <a href="{{ site.baseurl }}/">Home</a> &raquo;
    <span>Compare Versions</span>
  </nav>

  <h1>Compare Compliance Results</h1>

  <div class="compare-controls" style="display: flex; gap: 1rem; align-items: center; margin: 1.5rem 0;">
    <div>
      <label for="old-version"><strong>Old Version:</strong></label>
      <select id="old-version" onchange="runCompare()">
        {% assign version_pages = site.pages | where: "layout", "version" | sort: "version" %}
        {% for vp in version_pages %}
        <option value="{{ vp.version }}" {% if forloop.rindex == 2 %}selected{% endif %}>OCP {{ vp.version }}</option>
        {% endfor %}
      </select>
    </div>
    <span style="font-size: 1.5rem;">&#8594;</span>
    <div>
      <label for="new-version"><strong>New Version:</strong></label>
      <select id="new-version" onchange="runCompare()">
        {% for vp in version_pages %}
        <option value="{{ vp.version }}" {% if forloop.last %}selected{% endif %}>OCP {{ vp.version }}</option>
        {% endfor %}
      </select>
    </div>
  </div>

  <div id="compare-results"></div>
</div>

<script>
var versionData = {};
{% for vp in version_pages %}
{% assign vs = vp.version | replace: ".", "_" %}
{% assign df = "ocp-" | append: vs %}
{% if site.data[df] %}
versionData["{{ vp.version }}"] = {{ site.data[df] | jsonify }};
{% endif %}
{% endfor %}

function buildCheckMap(data) {
  var checks = {};
  var sections = [["remediations", "FAIL"], ["passing_checks", "PASS"]];
  var severities = ["high", "medium", "low"];
  sections.forEach(function(pair) {
    var section = pair[0], status = pair[1];
    severities.forEach(function(sev) {
      (data[section] && data[section][sev] || []).forEach(function(item) {
        checks[item.name] = {status: status, severity: item.severity || sev, platform: item.platform || ""};
      });
    });
  });
  (data.manual_checks || []).forEach(function(item) {
    checks[item.name] = {status: "MANUAL", severity: item.severity || "", platform: item.platform || ""};
  });
  return checks;
}

var regressions, fixes, added, removed, manualChanges;

function runCompare() {
  var oldV = document.getElementById('old-version').value;
  var newV = document.getElementById('new-version').value;
  var el = document.getElementById('compare-results');

  regressions = []; fixes = []; added = []; removed = []; manualChanges = [];

  if (oldV === newV) {
    el.innerHTML = '<p style="color: var(--color-text-muted);">Select two different versions to compare.</p>';
    return;
  }

  var oldData = versionData[oldV];
  var newData = versionData[newV];

  if (!oldData || !newData) {
    el.innerHTML = '<p style="color: var(--color-fail);">No scan data available for one or both versions.</p>';
    return;
  }

  var oldChecks = buildCheckMap(oldData);
  var newChecks = buildCheckMap(newData);

  var oldNames = Object.keys(oldChecks);
  var newNames = Object.keys(newChecks);
  var allNames = new Set(oldNames.concat(newNames));

  allNames.forEach(function(name) {
    var o = oldChecks[name], n = newChecks[name];
    if (!o) { added.push({name: name, status: n.status, platform: n.platform}); return; }
    if (!n) { removed.push({name: name, status: o.status, platform: o.platform}); return; }
    if (o.status === n.status) return;
    var entry = {name: name, old: o.status, new: n.status, platform: n.platform};
    if (o.status === 'PASS' && n.status === 'FAIL') regressions.push(entry);
    else if (o.status === 'FAIL' && n.status === 'PASS') fixes.push(entry);
    else manualChanges.push(entry);
  });

  var os = oldData.summary, ns = newData.summary;
  var html = '<div style="display:flex;gap:0.5rem;margin-bottom:1rem;">' +
    '<button class="quick-link export-btn" onclick="exportCompareJSON()">&#128230; Export JSON</button>' +
    '<button class="quick-link export-btn" onclick="exportCompareCSV()">&#128196; Export CSV</button>' +
    '</div>';
  html += '<div class="summary-cards" style="margin: 1rem 0;">';
  html += summaryCard('', 'Old: ' + oldV, 'New: ' + newV, 'Delta');
  html += summaryCard('Total', os.total_checks, ns.total_checks);
  html += summaryCard('Passing', os.passing, ns.passing);
  html += summaryCard('Failing', os.failing, ns.failing);
  html += summaryCard('Manual', os.manual, ns.manual);
  html += '</div>';

  if (regressions.length) {
    html += changeSection('Regressions (PASS &rarr; FAIL)', regressions, 'regression', true);
  }
  if (fixes.length) {
    html += changeSection('Fixes (FAIL &rarr; PASS)', fixes, 'fix', true);
  }
  if (manualChanges.length) {
    html += changeSection('Other Status Changes', manualChanges, 'other', true);
  }
  if (added.length) {
    html += changeSection('New Checks (not in ' + oldV + ')', added, 'added', false);
  }
  if (removed.length) {
    html += changeSection('Removed Checks (not in ' + newV + ')', removed, 'removed', false);
  }

  var total = regressions.length + fixes.length + added.length + removed.length + manualChanges.length;
  if (total === 0) {
    html += '<p>No differences found between ' + oldV + ' and ' + newV + '.</p>';
  } else {
    html += '<p style="margin-top: 1rem; color: var(--color-text-secondary);">' + total + ' total difference(s): ' +
      regressions.length + ' regressions, ' + fixes.length + ' fixes, ' +
      added.length + ' new, ' + removed.length + ' removed, ' +
      manualChanges.length + ' other</p>';
  }

  el.innerHTML = html;
  if (window.initSortable) window.initSortable(el);
  history.replaceState(null, '', '#left=' + encodeURIComponent(oldV) + '&right=' + encodeURIComponent(newV));
}

function summaryCard(label, oldVal, newVal, deltaLabel) {
  if (deltaLabel) {
    return '<div class="card" style="min-width:120px;text-align:center;">' +
      '<div style="font-weight:bold;margin-bottom:0.3rem;">' + label + '</div>' +
      '<div>' + oldVal + '</div><div>' + newVal + '</div>' +
      (deltaLabel ? '<div style="color:var(--color-text-secondary);font-size:0.8em;">' + deltaLabel + '</div>' : '') +
      '</div>';
  }
  var delta = newVal - oldVal;
  var sign = delta > 0 ? '+' : '';
  var cs = getComputedStyle(document.documentElement);
  var cFail = cs.getPropertyValue('--color-fail').trim() || '#c00';
  var cPass = cs.getPropertyValue('--color-pass').trim() || '#080';
  var cMuted = cs.getPropertyValue('--color-text-secondary').trim() || '#666';
  var color = label === 'Failing' ? (delta > 0 ? cFail : cPass) :
              label === 'Passing' ? (delta > 0 ? cPass : cFail) : cMuted;
  return '<div class="card" style="min-width:120px;text-align:center;">' +
    '<div style="font-weight:bold;margin-bottom:0.3rem;">' + label + '</div>' +
    '<div>' + oldVal + ' &rarr; ' + newVal + '</div>' +
    '<div style="color:' + color + ';font-weight:bold;">' + sign + delta + '</div></div>';
}

function changeSection(title, items, cls, showTransition) {
  var html = '<h3 style="margin-top:1.5rem;">' + title + ' (' + items.length + ')</h3>';
  html += '<table class="remediation-table"><thead><tr>';
  html += '<th class="sortable">Check Name</th><th class="sortable">Platform</th>';
  if (showTransition) html += '<th class="sortable">Change</th>';
  else html += '<th class="sortable">Status</th>';
  html += '</tr></thead><tbody>';
  items = items.slice().sort(function(a,b) { return a.name.localeCompare(b.name); });
  items.forEach(function(item) {
    var platform = item.platform === 'rhcos' ? '<span class="platform-badge rhcos">RHCOS</span>' :
                   item.platform === 'ocp' ? '<span class="platform-badge ocp">OCP</span>' : '-';
    html += '<tr><td><code>' + item.name + '</code></td><td>' + platform + '</td>';
    if (showTransition) html += '<td>' + item.old + ' &rarr; ' + item.new + '</td>';
    else html += '<td>' + item.status + '</td>';
    html += '</tr>';
  });
  html += '</tbody></table>';
  return html;
}

function exportCompareJSON() {
  if (!regressions) { alert('Run a comparison first.'); return; }
  var oldV = document.getElementById('old-version').value;
  var newV = document.getElementById('new-version').value;
  var data = {
    old_version: oldV,
    new_version: newV,
    exported_at: new Date().toISOString(),
    summary: {regressions: regressions.length, fixes: fixes.length, added: added.length, removed: removed.length, other: manualChanges.length},
    regressions: regressions,
    fixes: fixes,
    added: added,
    removed: removed,
    other_changes: manualChanges
  };
  downloadBlob(JSON.stringify(data, null, 2), 'application/json', 'compliance-compare-' + oldV + '-to-' + newV + '.json');
}

function exportCompareCSV() {
  if (!regressions) { alert('Run a comparison first.'); return; }
  var oldV = document.getElementById('old-version').value;
  var newV = document.getElementById('new-version').value;
  var rows = [['Category', 'Check Name', 'Platform', 'Old Status', 'New Status'].join(',')];
  function addRows(category, items, oldStatus, newStatus) {
    items.forEach(function(item) {
      rows.push([
        csvEscape(category),
        csvEscape(item.name),
        csvEscape(item.platform || ''),
        csvEscape(oldStatus !== null ? item[oldStatus] : ''),
        csvEscape(newStatus !== null ? item[newStatus] : '')
      ].join(','));
    });
  }
  addRows('regression', regressions, 'old', 'new');
  addRows('fix', fixes, 'old', 'new');
  addRows('other', manualChanges, 'old', 'new');
  addRows('added', added, null, 'status');
  addRows('removed', removed, 'status', null);
  downloadBlob(rows.join('\n'), 'text/csv', 'compliance-compare-' + oldV + '-to-' + newV + '.csv');
}

(function restoreFromHash() {
  var params = parseHash();
  if (params.left) document.getElementById('old-version').value = params.left;
  if (params.right) document.getElementById('new-version').value = params.right;
})();

runCompare();
</script>
