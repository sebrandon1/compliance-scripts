#!/usr/bin/env python3
"""Ensure the shell smoke test covers every directory that holds scripts.

`tests/shell-smoke-test.sh` is the fast syntax gate that CI runs. If a
directory with tracked shell scripts is left out of its DIRS array, a syntax
error there is not caught until shellcheck or the script itself runs.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SMOKE_TEST = REPO / "tests" / "shell-smoke-test.sh"

# Directories generated at runtime, vendored, or outside the automation tree.
EXCLUDED_PARTS = {
    ".git",
    ".claude",
    ".venv",
    "venv",
    "node_modules",
    ".mypy_cache",
    ".pytest_cache",
    "docs",
    "complianceremediations",
    "generated-networkpolicies",
    "test-results",
    "test-runs",
    "testing",
}


def _smoke_test_dirs() -> set[str]:
    text = SMOKE_TEST.read_text()
    match = re.search(r"^DIRS=\(([^)]*)\)", text, re.MULTILINE)
    assert match, "shell-smoke-test.sh must define a DIRS array"
    return set(match.group(1).split())


def _directories_with_scripts() -> set[str]:
    dirs: set[str] = set()
    for path in REPO.rglob("*.sh"):
        rel = path.relative_to(REPO)
        if len(rel.parts) < 2 or EXCLUDED_PARTS.intersection(rel.parts):
            continue
        dirs.add(rel.parts[0])
    return dirs


def test_core_script_dirs_are_checked() -> None:
    for directory in ("lib", "lab-tools", "tests"):
        assert directory in _smoke_test_dirs(), (
            f"{directory}/ contains shell scripts but is not smoke-tested"
        )


def test_no_script_directory_is_missed() -> None:
    missing = _directories_with_scripts() - _smoke_test_dirs()
    assert not missing, (
        "these directories contain .sh files but are not in DIRS: "
        + ", ".join(sorted(missing))
    )
