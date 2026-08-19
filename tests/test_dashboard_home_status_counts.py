#!/usr/bin/env python3
"""Static checks that the home page counts group status from tracking data."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
INDEX = (REPO / "docs" / "index.md").read_text()


def _breakdown_block() -> str:
    start = INDEX.index("{% include resolve-tracking.html version=version_page.version %}")
    end = INDEX.index("</p>", INDEX.index("status-breakdown"))
    return INDEX[start:end]


def test_home_counts_groups_from_tracking_not_page_frontmatter():
    block = _breakdown_block()
    assert "include resolve-tracking.html version=version_page.version" in INDEX
    assert "for g in tracking.groups" in block
    assert 'where: "status", "in_progress"' not in INDEX
    assert 'where: "status", "complete"' not in INDEX


def test_home_treats_verified_and_pass_vanilla_as_complete():
    block = _breakdown_block()
    assert 'g[1].status == "verified"' in block
    assert 'g[1].status contains "pass-vanilla"' in block
    assert "complete_count" in block


def test_home_still_counts_in_progress_pending_and_on_hold():
    block = _breakdown_block()
    assert 'g[1].status == "in_progress"' in block
    assert 'g[1].status == "pending"' in block
    assert 'g[1].status == "on_hold"' in block
