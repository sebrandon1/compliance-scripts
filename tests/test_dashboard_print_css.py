#!/usr/bin/env python3
"""Static checks for the dashboard print stylesheet."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CSS = (REPO / "docs" / "assets" / "css" / "style.css").read_text()


def _print_block() -> str:
    idx = CSS.index("@media print")
    return CSS[idx:]


def test_print_stylesheet_exists():
    assert "@media print" in CSS


def test_print_hides_chrome():
    block = _print_block()
    for selector in (
        ".floating-legend",
        ".keyboard-help-modal",
        "header",
        "footer",
        ".filter-buttons",
        ".skip-link",
    ):
        assert selector in block


def test_print_expands_details_and_rows():
    block = _print_block()
    assert ".scan-detail" in block
    assert ".group-detail" in block
    assert "details" in block
    assert "break-inside: avoid" in block
