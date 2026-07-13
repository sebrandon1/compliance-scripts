// Shared filter/search JavaScript for remediations pages.
// Supports both data-attribute mode (4.22+) and text-matching mode (4.21).

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
  document.querySelectorAll('.filter-btn:not(.platform-filter):not(.upstream-filter)').forEach(function(b) {
    b.classList.remove('active');
  });
  var btn = document.querySelector('[data-filter="' + filter + '"]');
  if (btn) btn.classList.add('active');
  filterTables();
}

function setPlatformFilter(platform) {
  currentPlatform = platform;
  document.querySelectorAll('.platform-filter').forEach(function(b) {
    b.classList.remove('active');
  });
  var btn = document.querySelector('[data-platform="' + platform + '"]');
  if (btn) btn.classList.add('active');
  filterTables();
}

function setUpstreamFilter(upstream) {
  currentUpstream = upstream;
  document.querySelectorAll('.upstream-filter').forEach(function(b) {
    b.classList.remove('active');
  });
  var btn = document.querySelector('[data-upstream="' + upstream + '"]');
  if (btn) btn.classList.add('active');
  filterTables();
}

function filterTables() {
  var search = (document.getElementById('table-search').value || '').toLowerCase();
  var remTable = document.getElementById('remediation-table');

  if (remTable) {
    // Data-attribute mode (4.22+): uses data-status, data-platform, etc.
    var rows = remTable.querySelectorAll('tbody tr');
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
  } else {
    // Text-matching mode (4.21): scans all tables by text content
    var tables = document.querySelectorAll('table');
    var visibleCount = 0;
    var totalCount = 0;
    tables.forEach(function(table) {
      var rows = table.querySelectorAll('tbody tr, tr:not(:first-child)');
      rows.forEach(function(row) {
        if (row.querySelector('th')) return;
        totalCount++;
        var text = row.textContent.toLowerCase();
        var statusMatch = text.match(/(pending|in progress|on hold|complete)/i);
        var status = statusMatch ? statusMatch[0].toLowerCase() : '';
        var matchesSearch = !search || text.indexOf(search) !== -1;
        var matchesFilter = currentFilter === 'all' ||
          (currentFilter === 'pending' && status === 'pending') ||
          (currentFilter === 'in_progress' && status === 'in progress') ||
          (currentFilter === 'on_hold' && status === 'on hold') ||
          (currentFilter === 'complete' && status === 'complete');
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
