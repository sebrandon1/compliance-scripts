#!/usr/bin/env python3
"""Static checks for core/export-compliance-data.sh dependencies."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = (REPO / "core" / "export-compliance-data.sh").read_text()


def test_require_cmd_includes_bc():
    assert "require_cmd oc jq bc" in SCRIPT


def test_header_lists_bc_as_required():
    assert "Requires: oc, jq, bc" in SCRIPT


def test_preflight_requires_bc():
    preflight = (REPO / "scripts" / "preflight-check.sh").read_text()
    assert "bc" in preflight
    assert "REQUIRED_TOOLS=(oc yq jq python3 bc)" in preflight
