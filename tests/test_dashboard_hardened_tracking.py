#!/usr/bin/env python3
"""Static checks that Hardened uses the latest version's tracking, not 4.22."""
from __future__ import annotations

import json
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


def test_hero_stats_do_not_hardcode_group_remediation_or_rhcos_numbers():
    assert "Mapped from 592" not in HARDENED
    assert "<span class=\"number\">97%</span>" not in HARDENED
    assert "452 &rarr; 14" not in HARDENED
    assert "mapped_failing_manual" in HARDENED
    assert "rhcos_pct" in HARDENED
    assert "site.data.scan-history" in HARDENED
    assert 'notes contains "vanilla scan"' in HARDENED
    assert 'notes contains "with hardening"' in HARDENED


def test_scan_history_supports_rhcos_reduction_formula():
    history = json.loads((REPO / "docs" / "_data" / "scan-history.json").read_text())
    vanilla = [
        e["summary"]["rhcos_failing"]
        for e in history
        if e.get("notes") and "vanilla scan" in e["notes"].lower()
        and e.get("summary", {}).get("rhcos_failing") is not None
    ]
    hardened = [
        e["summary"]["rhcos_failing"]
        for e in history
        if e.get("notes") and "with hardening" in e["notes"].lower()
        and e.get("summary", {}).get("rhcos_failing") is not None
    ]
    assert vanilla, "need a vanilla scan with rhcos_failing"
    assert hardened, "need a hardening scan with rhcos_failing"
    before = max(vanilla)
    after = min(hardened)
    assert before > after
    pct = round((before - after) * 100 / before)
    assert 0 < pct <= 100
