var currentFilter = 'all';
var currentUpstream = 'all';

function setStatusFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-btn:not(.upstream-filter)').forEach(function(btn) {
    btn.classList.remove('active');
  });
  var btn = document.querySelector('[data-filter="' + filter + '"]');
  if (btn) btn.classList.add('active');
  filterTables();
}

function setUpstreamFilter(upstream) {
  currentUpstream = upstream;
  document.querySelectorAll('.upstream-filter').forEach(function(btn) {
    btn.classList.remove('active');
  });
  var btn = document.querySelector('[data-upstream="' + upstream + '"]');
  if (btn) btn.classList.add('active');
  filterTables();
}

function getGroupId(row) {
  var link = row.querySelector('a[href]');
  if (link) {
    var match = link.getAttribute('href').match(/([A-Z]+\d+)\.html/);
    if (match) return match[1];
  }
  return null;
}

function filterTables() {
  var searchInput = document.getElementById('table-search');
  var searchTerm = searchInput ? searchInput.value.toLowerCase() : '';
  var tables = document.querySelectorAll('table');
  var visibleCount = 0;
  var totalCount = 0;
  var verdicts = typeof upstreamVerdicts !== 'undefined' ? upstreamVerdicts : {};
  var branches = typeof hasBranch !== 'undefined' ? hasBranch : {};

  tables.forEach(function(table) {
    var rows = table.querySelectorAll('tbody tr, tr:not(:first-child)');
    rows.forEach(function(row) {
      if (row.querySelector('th')) return;
      var groupId = getGroupId(row);
      if (!groupId) return;
      totalCount++;
      var text = row.textContent.toLowerCase();
      var status = (typeof groupStatuses !== 'undefined' && groupStatuses[groupId]) || '';
      var verdict = verdicts[groupId] || '';

      var matchesSearch = searchTerm === '' || text.includes(searchTerm);
      var matchesFilter = statusMatchesFilter(status, currentFilter);
      var matchesUpstream = currentUpstream === 'all' || verdict === currentUpstream ||
        (currentUpstream === 'has-branch' && branches[groupId]);

      if (matchesSearch && matchesFilter && matchesUpstream) {
        row.style.display = '';
        visibleCount++;
      } else {
        row.style.display = 'none';
      }
    });
  });

  var counts = document.getElementById('filter-counts');
  if (counts) {
    counts.textContent =
      visibleCount === totalCount ? '' : 'Showing ' + visibleCount + ' of ' + totalCount;
  }
}
