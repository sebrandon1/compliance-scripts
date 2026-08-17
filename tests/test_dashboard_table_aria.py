#!/usr/bin/env python3
"""Static ARIA checks for remediation and passing table partials."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
REMEDIATION = (
    REPO / "docs" / "_includes" / "remediation-table.html"
).read_text()
PASSING = (REPO / "docs" / "_includes" / "passing-table.html").read_text()


def test_remediation_table_has_aria_label():
    assert 'aria-label="Failing compliance checks"' in REMEDIATION


def test_passing_table_has_aria_label():
    assert 'aria-label="Passing compliance checks"' in PASSING


def test_copy_buttons_have_accessible_name_and_live():
    for src in (REMEDIATION, PASSING):
        assert 'aria-label="Copy check name"' in src
        assert 'aria-live="polite"' in src
        assert 'title="Copy check name"' in src


def test_remediation_details_summary_has_aria_label():
    assert 'aria-label="{{ check.name }} remediation details"' in REMEDIATION
    assert "<details" in REMEDIATION
    assert "<summary" in REMEDIATION
