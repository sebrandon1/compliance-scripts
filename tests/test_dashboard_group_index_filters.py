#!/usr/bin/env python3
"""Static checks that group index status filters match remediations.html."""
from __future__ import annotations

import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DOCS = REPO / "docs"
INDEXES = sorted((DOCS / "versions").glob("*/groups/index.md"))
BUTTONS = (DOCS / "_includes" / "status-filter-buttons.html").read_text()
FILTER_JS = (DOCS / "assets" / "js" / "status-filter.js").read_text()
FILTERS_JS = (DOCS / "assets" / "js" / "filters.js").read_text()


def test_shared_buttons_match_remediation_statuses():
    for key in ("pass-vanilla", "verified", "in_progress", "pending", "partial"):
        assert f'data-filter="{key}"' in BUTTONS
    assert 'data-filter="complete"' not in BUTTONS
    assert 'data-filter="on_hold"' not in BUTTONS


def test_group_indexes_use_shared_status_filters():
    assert INDEXES, "expected at least one groups/index.md"
    for path in INDEXES:
        text = path.read_text()
        assert "status-filter-buttons.html" in text, path
        assert "group-statuses-js.html" in text, path
        assert "group-index-filters.js" in text, path
        assert "status-filter.js" in text, path
        assert 'data-filter="complete"' not in text, path
        assert "statusCell.includes('Complete')" not in text, path


def test_four_twenty_one_index_has_version_frontmatter():
    text = (DOCS / "versions" / "4.21" / "groups" / "index.md").read_text()
    assert 'version: "4.21"' in text


def test_status_matches_filter_handles_pass_vanilla_prefix():
    assert "status.indexOf('pass-vanilla')" in FILTER_JS
    assert "statusMatchesFilter(status, currentFilter)" in FILTERS_JS
    group_js = (DOCS / "assets" / "js" / "group-index-filters.js").read_text()
    assert "statusMatchesFilter(status, currentFilter)" in group_js


def test_status_matches_filter_js_cases():
    script = r"""
const fs = require('fs');
eval(fs.readFileSync(process.argv[1], 'utf8'));
const cases = [
  ['pass-vanilla', 'pass-vanilla', true],
  ['pass-vanilla-rhcos9.8', 'pass-vanilla', true],
  ['verified', 'verified', true],
  ['verified-needed', 'verified', false],
  ['pending', 'all', true],
  ['partial', 'partial', true],
  ['in_progress', 'complete', false],
  ['', 'pending', false],
];
for (const [status, filter, expected] of cases) {
  const got = statusMatchesFilter(status, filter);
  if (got !== expected) {
    console.error(status, filter, 'got', got, 'expected', expected);
    process.exit(1);
  }
}
"""
    result = subprocess.run(
        ["node", "-e", script, str(DOCS / "assets" / "js" / "status-filter.js")],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr or result.stdout
