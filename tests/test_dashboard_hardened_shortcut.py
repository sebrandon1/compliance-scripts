#!/usr/bin/env python3
"""Static checks for Hardened Quick Link and g e shortcut."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
INDEX = (REPO / "docs" / "index.md").read_text()
DEFAULT = (REPO / "docs" / "_layouts" / "default.html").read_text()


def test_home_quick_links_include_hardened():
    quick = INDEX[INDEX.index("## Quick Links"):INDEX.index("## How It Works")]
    assert "/hardened" in quick
    assert "Hardened" in quick


def test_ge_shortcut_goes_to_hardened():
    assert "e.key === 'e'" in DEFAULT
    assert "/hardened" in DEFAULT
    assert "Go to Hardened" in DEFAULT


def test_gh_home_shortcut_still_present():
    assert "e.key === 'h'" in DEFAULT
    assert "Go to home" in DEFAULT
