#!/usr/bin/env python3
"""Assert default run-artifact directories are git-ignored (issue #447).

`verify-all-groups.sh` and `organize-machine-configs.sh` write under
`test-results/`, but `.gitignore` only listed `test-runs/`. Running either
tool left a large untracked tree that could be committed by accident.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GITIGNORE = REPO / ".gitignore"

# (script, regex whose first group is the default output directory literal)
DEFAULT_OUTPUT_DIRS = [
    (
        REPO / "scripts" / "verify-all-groups.sh",
        re.compile(r'OUTPUT_DIR="([^"]+)"'),
    ),
    (
        REPO / "core" / "organize-machine-configs.sh",
        re.compile(r'results_dir="([^"]+)"'),
    ),
]


def _ignored_top_dirs(gitignore: Path = GITIGNORE) -> set[str]:
    patterns = set()
    for line in gitignore.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.add(line.rstrip("/"))
    return patterns


def _unignored_output_dirs(gitignore: Path) -> list[str]:
    """Return "<script>:<dir>" for default output dirs missing from gitignore."""
    ignored = _ignored_top_dirs(gitignore)
    missing = []
    for script, pattern in DEFAULT_OUTPUT_DIRS:
        literals = [m for m in pattern.findall(script.read_text()) if m]
        assert literals, f"{script.name} must define a default output directory"
        literal = literals[-1]
        # "test-results/$(date ...)" and "test-results/$ts" -> "test-results"
        top = literal.split("/", 1)[0].split("$", 1)[0].strip("/")
        assert top, f"{script.name} default output dir is empty"
        if top not in ignored:
            missing.append(f"{script.name}:{top}")
    return missing


def test_script_output_dirs_are_gitignored():
    assert _unignored_output_dirs(GITIGNORE) == []


def test_missing_entry_is_detected(tmp_path):
    """The check must actually fail when an output dir is not ignored."""
    partial = tmp_path / ".gitignore"
    partial.write_text("test-runs/\n")
    assert _unignored_output_dirs(partial) == [
        "verify-all-groups.sh:test-results",
        "organize-machine-configs.sh:test-results",
    ]


def test_legacy_test_runs_still_ignored():
    # Historical docs and scripts still reference test-runs/.
    assert "test-runs" in _ignored_top_dirs()
