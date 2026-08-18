#!/usr/bin/env python3
"""Static checks that Hardened uses the latest version's tracking, not 4.22."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HARDENED = (REPO / "docs" / "_layouts" / "hardened.html").read_text()
RESOLVE = (REPO / "docs" / "_includes" / "resolve-tracking.html").read_text()


def test_does_not_hardcode_tracking_4_22():
    assert "tracking-4_22" not in HARDENED
    assert "t422" not in HARDENED


def test_resolves_tracking_from_latest_version_page():
    assert "version_pages.first" in HARDENED
    assert "resolve-tracking.html" in HARDENED
    assert "version=latest_vp.version" in HARDENED
    assert "include.version | default: page.version" in RESOLVE


def test_hero_stats_use_latest_tracking_counts():
    assert "On OCP {{ latest_vp.version }}" in HARDENED
    assert "{{ ref_tracking.groups.size }}" in HARDENED
    assert "{{ ref_tracking.remediations.size }}" in HARDENED
    assert "{{ ref_tracking.meta.upstream_pr_count }}" in HARDENED
