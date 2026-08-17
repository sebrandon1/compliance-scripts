function isExpandableDetail(row) {
  return row.classList.contains('scan-detail') || row.classList.contains('group-detail');
}

function setExpandableRow(row, expanded) {
  if (!row) return;
  var detail = row.nextElementSibling;
  if (!detail || !isExpandableDetail(detail)) return;
  var currentlyExpanded = detail.style.display !== 'none';
  if (currentlyExpanded === expanded) return;
  detail.style.display = expanded ? '' : 'none';
  row.setAttribute('aria-expanded', expanded ? 'true' : 'false');
  var btn = row.querySelector('.expand-toggle');
  if (btn) {
    btn.setAttribute('aria-label', expanded ? 'Collapse details' : 'Expand details');
  }
}

function toggleExpandableRow(row) {
  if (!row) return;
  setExpandableRow(row, row.getAttribute('aria-expanded') !== 'true');
}
