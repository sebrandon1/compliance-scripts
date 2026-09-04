#!/usr/bin/env python3
"""Static checks for version page severity filter buttons and JS (issue #284)."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VERSION_HTML = (REPO / "docs" / "_layouts" / "version.html").read_text()

_SEVERITIES = ("high", "medium", "low", "manual")


def test_severity_filter_buttons_all_present():
    for sev in ("all", *_SEVERITIES):
        assert f'data-severity="{sev}"' in VERSION_HTML, f"missing data-severity={sev} button"


def test_severity_filter_all_button_starts_active():
    assert 'class="filter-btn severity-filter active" data-severity="all"' in VERSION_HTML


def test_severity_filter_non_all_buttons_have_class():
    assert VERSION_HTML.count('class="filter-btn severity-filter"') == len(_SEVERITIES)


def test_failing_sections_have_data_severity():
    for sev in _SEVERITIES:
        assert f'class="remediation-section" data-severity="{sev}"' in VERSION_HTML, \
            f"missing data-severity={sev} on a failing section"


def test_passing_sections_have_data_severity():
    for sev in ("high", "medium", "low"):
        # Each sev appears on both a failing and a passing section
        assert VERSION_HTML.count(f'data-severity="{sev}"') >= 2, \
            f"expected data-severity={sev} on both failing and passing sections"


def test_set_severity_filter_function_defined():
    assert "function setSeverityFilter(sev)" in VERSION_HTML


def test_current_severity_filter_variable_initialized():
    assert "var currentSeverityFilter = 'all';" in VERSION_HTML


def test_update_hash_includes_severity():
    assert "params.push('severity=' + currentSeverityFilter)" in VERSION_HTML


def test_restore_from_hash_reads_severity():
    assert "if (h.severity) setSeverityFilter(h.severity);" in VERSION_HTML


def test_set_check_filter_does_not_clobber_severity_buttons():
    assert ".filter-btn:not(.severity-filter)" in VERSION_HTML


def test_set_severity_filter_scoped_to_filter_bar():
    assert ".filter-bar .severity-filter" in VERSION_HTML


def test_filter_checks_skips_hidden_sections():
    assert "!visibleSections.has(section)) return;" in VERSION_HTML


def test_filter_checks_hides_non_matching_sections():
    assert "currentSeverityFilter === 'all' || sev === currentSeverityFilter" in VERSION_HTML
