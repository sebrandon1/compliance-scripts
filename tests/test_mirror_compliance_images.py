#!/usr/bin/env python3
"""Behavioral tests for utilities/mirror-compliance-images.sh (issue #421)."""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "utilities" / "mirror-compliance-images.sh"
MAKEFILE = REPO / "Makefile"


def test_existing_images_exit_cleanly_without_detection(stub_binary, run_script):
    # Every skopeo inspect succeeds, so nothing is mirrored or built.
    stub_binary("skopeo", "#!/bin/sh\nexit 0\n")

    result = run_script(SCRIPT, "v1.9.0")
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "All images already exist" in output
    # An explicit version means release detection must never run.
    assert "Auto-detecting" not in output


_TARGET_HEADING = re.compile(r"^([A-Za-z0-9_.-]+):", re.MULTILINE)


def _make_target(name: str) -> str:
    """The recipe lines for `name`, up to the next top-level target."""
    text = MAKEFILE.read_text()
    heading = re.search(rf"^{name}:.*$", text, re.MULTILINE)
    assert heading, f"{name} target not found"
    rest = text[heading.end():]
    following = _TARGET_HEADING.search(rest)
    return rest[: following.start()] if following else rest


def test_make_target_delegates_to_the_script():
    # Issue #422: a second inline mirror loop silently produced an incomplete
    # image set, so the target must forward to the one maintained implementation.
    target = _make_target("mirror-images")
    assert re.search(
        r'^[ \t]*@FORCE=.*\./utilities/mirror-compliance-images\.sh "\$\(CO_REF\)"$',
        target,
        re.MULTILINE,
    ), target
    assert "skopeo copy" not in target


def test_make_target_keeps_ref_and_skopeo_guards():
    target = _make_target("mirror-images")
    assert "CO_REF is required" in target
    assert "command -v skopeo" in target
    assert target.count("exit 1") == 2
