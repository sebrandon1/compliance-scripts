#!/usr/bin/env python3
"""Static checks for misc/apply-remediations-by-severity.sh path resolution."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = (REPO / "misc" / "apply-remediations-by-severity.sh").read_text()


def test_script_dir_resolves_to_repo_root():
    assert 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' in SCRIPT


def test_src_dir_uses_repo_root_not_misc():
    assert 'SRC_DIR="$SCRIPT_DIR/complianceremediations"' in SCRIPT
    assert 'SRC_DIR="$REPO_DIR/complianceremediations"' not in SCRIPT


def test_report_path_uses_repo_root():
    assert 'report_path="$SCRIPT_DIR/applied-yamls-' in SCRIPT
    assert 'report_path="$REPO_DIR/' not in SCRIPT


def test_does_not_recompute_repo_dir_from_script_dirname():
    assert 'dirname "$0"' not in SCRIPT
