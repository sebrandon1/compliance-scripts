#!/usr/bin/env python3
"""Checks that CO release detection is authenticated and fails loudly (issue #414)."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOWS = REPO / ".github" / "workflows"
WORKFLOW = WORKFLOWS / "verify-mirror-architectures.yml"
MIRROR_WORKFLOW = WORKFLOWS / "mirror-compliance-images.yml"
DETECT_SCRIPT = REPO / "scripts" / "detect-co-release.sh"
VERIFY_SCRIPT = REPO / "utilities" / "verify-mirror-architectures.sh"


def _detect_step(text: str) -> str:
    start = text.index("- name: Detect latest CO release")
    end = text.index("- name: Verify mirror image architectures")
    return text[start:end]


def test_detect_step_uses_shared_authenticated_script():
    step = _detect_step(WORKFLOW.read_text())
    assert "GH_TOKEN: ${{ github.token }}" in step
    assert "./scripts/detect-co-release.sh" in step
    assert "api.github.com" not in step


def test_mirror_workflow_uses_shared_detection():
    text = MIRROR_WORKFLOW.read_text()
    assert "./scripts/detect-co-release.sh" in text
    assert "api.github.com" not in text


def test_detect_script_prints_latest_release(stub_binary, run_script):
    stub_binary("gh", "#!/bin/sh\necho '{\"tag_name\": \"v1.9.0\"}'\n")
    result = run_script(DETECT_SCRIPT)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip() == "v1.9.0"


def test_detect_script_falls_back_to_newest_tag(stub_binary, run_script):
    stub_binary(
        "gh",
        """#!/bin/sh
case "$*" in
  *releases/latest*) echo '{"tag_name": null}' ;;
  *) echo '[{"name":"v1.8.0"},{"name":"v1.9.2"},{"name":"v1.10.0"}]' ;;
esac
""",
    )
    result = run_script(DETECT_SCRIPT)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.strip() == "v1.10.0"


def test_detect_script_fails_loudly(stub_binary, run_script):
    stub_binary("gh", "#!/bin/sh\nexit 1\n")
    result = run_script(DETECT_SCRIPT)
    assert result.returncode == 1
    assert "Could not detect" in result.stdout + result.stderr


def test_verify_script_rejects_empty_tag(stub_binary, run_script):
    stub_binary("jq", "#!/bin/sh\nexit 0\n")
    stub_binary("skopeo", "#!/bin/sh\nexit 0\n")

    result = run_script(VERIFY_SCRIPT, "quay.io/bapalm/compliance-operator:")
    output = result.stdout + result.stderr
    assert result.returncode == 1, output
    assert "empty tag" in output
