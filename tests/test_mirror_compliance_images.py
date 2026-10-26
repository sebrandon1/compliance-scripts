#!/usr/bin/env python3
"""Behavioral tests for utilities/mirror-compliance-images.sh (issue #421)."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "utilities" / "mirror-compliance-images.sh"


def test_existing_images_exit_cleanly_without_detection(stub_binary, run_script):
    # Every skopeo inspect succeeds, so nothing is mirrored or built.
    stub_binary("skopeo", "#!/bin/sh\nexit 0\n")

    result = run_script(SCRIPT, "v1.9.0")
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "All images already exist" in output
    # An explicit version means release detection must never run.
    assert "Auto-detecting" not in output
