#!/usr/bin/env python3
"""Static checks for keyboard-accessible expandable dashboard rows."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HARDENED = (REPO / "docs" / "_layouts" / "hardened.html").read_text()
DEFAULT = (REPO / "docs" / "_layouts" / "default.html").read_text()
EXPAND_JS = (REPO / "docs" / "assets" / "js" / "expand-rows.js").read_text()


def test_scan_rows_have_aria_and_tabindex():
    assert 'tabindex="0"' in HARDENED
    assert 'aria-expanded="false"' in HARDENED
    assert 'aria-controls="scan-detail-{{ forloop.index }}"' in HARDENED
    assert 'id="scan-detail-{{ forloop.index }}"' in HARDENED


def test_group_rows_have_aria_and_tabindex():
    assert 'aria-controls="group-detail-{{ gid }}"' in HARDENED
    assert 'id="group-detail-{{ gid }}"' in HARDENED
    assert 'class="expand-toggle"' in HARDENED
    assert 'aria-label="Expand details"' in HARDENED


def test_expandable_rows_call_shared_toggle():
    assert 'onclick="toggleExpandableRow(this)"' in HARDENED
    assert "function toggleScanDetail" not in HARDENED
    assert "function toggleGroupDetail" not in HARDENED
    assert "function toggleExpandableRow(row)" in EXPAND_JS
    assert "expand-rows.js" in DEFAULT


def test_activate_selected_row_prefers_expandable():
    idx = DEFAULT.index("function activateSelectedRow()")
    body = DEFAULT[idx:idx + 800]
    expand_at = body.index("classList.contains('expandable')")
    link_at = body.index("querySelector('a')")
    assert expand_at < link_at
    assert "if (selectedRowIndex < 0) return false" in body


def test_get_visible_rows_excludes_detail_rows():
    idx = DEFAULT.index("function getVisibleRows()")
    body = DEFAULT[idx:idx + 500]
    assert "isExpandableDetail(row)" in body


def test_enter_and_space_skip_links_and_buttons():
    idx = DEFAULT.index("case 'Enter':")
    body = DEFAULT[idx:idx + 700]
    assert "case ' ':" in body
    assert "closest('a')" in body
    assert "closest('button')" in body


def test_toggle_updates_aria_expanded_and_button_label():
    assert "function setExpandableRow(row, expanded)" in EXPAND_JS
    assert "aria-expanded" in EXPAND_JS
    assert "Collapse details" in EXPAND_JS
    assert "Expand details" in EXPAND_JS
    assert "if (!row) return" in EXPAND_JS


def test_filters_collapse_via_shared_helper():
    assert "setExpandableRow(row, false)" in HARDENED
