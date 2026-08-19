#!/usr/bin/env python3
"""Static checks for projected coverage on version pages."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VERSION = (REPO / "docs" / "_layouts" / "version.html").read_text()


def _projected_block() -> str:
    start = VERSION.index("id=\"projected-coverage\"")
    end = VERSION.index("stat-note", start)
    return VERSION[start:end]


def test_projected_coverage_counts_one_check_per_remediation():
    block = _projected_block()
    assert "for rem in tracking.remediations" in block
    assert "{% assign fixable = fixable | plus: 1 %}" in block
    assert "plus: 2" not in block


def test_projected_coverage_only_counts_in_progress_groups():
    block = _projected_block()
    assert 'group.status == "in_progress"' in block
