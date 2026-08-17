#!/usr/bin/env python3
"""Static checks for compare-page version defaults."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
COMPARE = (REPO / "docs" / "compare.md").read_text()


def _old_select_block() -> str:
    start = COMPARE.index('id="old-version"')
    end = COMPARE.index("</select>", start)
    return COMPARE[start:end]


def _new_select_block() -> str:
    start = COMPARE.index('id="new-version"')
    end = COMPARE.index("</select>", start)
    return COMPARE[start:end]


def test_old_version_defaults_to_second_newest():
    block = _old_select_block()
    assert "forloop.rindex == 2" in block
    assert "forloop.last" not in block


def test_new_version_defaults_to_latest():
    block = _new_select_block()
    assert "forloop.last" in block
    assert "selected" in block
