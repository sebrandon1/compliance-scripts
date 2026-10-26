#!/usr/bin/env python3
"""Behavioral tests for scripts/detect-co-release.sh (issue #420).

The curl fallback used to run unauthenticated, so a rate-limited runner looked
exactly like a missing release. It must send credentials and must never print
an empty tag.
"""
from __future__ import annotations

import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "detect-co-release.sh"
INSTALL_SCRIPT = REPO / "core" / "install-compliance-operator.sh"

# Force the curl branch: the only entries on PATH are our stubs.
_NO_TOOLS_PATH = "/nonexistent"

_CURL_RECORDING_STUB = """#!/bin/sh
printf '%s\\n' "$@" > "$CURL_ARGS"
printf '%s' '{"tag_name":"v1.9.0"}'
"""

_CURL_FAILING_STUB = """#!/bin/sh
exit 22
"""


def _link_jq(stub_dir):
    """Link the real jq into stub_dir so the script's preflight passes."""
    jq = shutil.which("jq")
    assert jq, "jq is required to run this test"
    (stub_dir / "jq").symlink_to(jq)


def test_curl_fallback_sends_authorization_when_token_set(
    stub_dir, stub_binary, run_script, tmp_path
):
    _link_jq(stub_dir)
    stub_binary("curl", _CURL_RECORDING_STUB)
    args_file = tmp_path / "curl-args"

    result = run_script(
        SCRIPT,
        env={"GH_TOKEN": "test-token", "CURL_ARGS": str(args_file), "PATH": _NO_TOOLS_PATH},
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "v1.9.0"
    curl_args = args_file.read_text()
    assert "Authorization: Bearer test-token" in curl_args
    assert "Accept: application/vnd.github+json" in curl_args


def test_curl_fallback_omits_authorization_without_token(stub_dir, stub_binary, run_script, tmp_path):
    _link_jq(stub_dir)
    stub_binary("curl", _CURL_RECORDING_STUB)
    args_file = tmp_path / "curl-args"

    result = run_script(SCRIPT, env={"CURL_ARGS": str(args_file), "PATH": _NO_TOOLS_PATH})

    assert result.returncode == 0, result.stderr
    assert "Authorization" not in args_file.read_text()


def test_failed_api_call_exits_nonzero_instead_of_printing_empty_tag(
    stub_dir, stub_binary, run_script
):
    _link_jq(stub_dir)
    stub_binary("curl", _CURL_FAILING_STUB)

    result = run_script(SCRIPT, env={"PATH": _NO_TOOLS_PATH})

    assert result.returncode != 0
    assert result.stdout.strip() == ""
    assert "Could not detect the latest Compliance Operator release" in result.stderr


def test_install_script_uses_the_shared_detector_and_warns_loudly():
    text = INSTALL_SCRIPT.read_text()
    assert "get_latest_release_tag" not in text
    assert 'scripts/detect-co-release.sh' in text
    assert (
        "Could not detect the latest release (network/rate limit); falling back to 'master'"
        in text
    )
