#!/usr/bin/env python3
"""Behavioral tests for the rootfs extraction checks in rhcos-static-scan.sh.

An empty or truncated rootfs previously produced a scan full of file-not-found
FAILs that looked like real compliance results. These tests drive the script's
extraction path with stubbed podman/tar/oc and assert it aborts instead.
"""
from __future__ import annotations

from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "rhcos-static-scan.sh"

OC_STUB = """#!/bin/sh
echo "quay.io/example/rhcos:4.22.0"
exit 0
"""

PODMAN_STUB = """#!/bin/sh
cmd="$1"
shift
case "$cmd" in
  cp)
    # podman cp <container>:<path> <dest>
    : > "$2"
    ;;
esac
exit 0
"""


def _tar_stub(body: str) -> str:
    return (
        "#!/bin/sh\n"
        "dir=\"\"\n"
        "prev=\"\"\n"
        "for arg in \"$@\"; do\n"
        "  if [ \"$prev\" = \"-C\" ]; then dir=\"$arg\"; fi\n"
        "  prev=\"$arg\"\n"
        "done\n"
        + body
    )


TAR_EMPTY = _tar_stub("exit 0\n")
TAR_NO_USR = _tar_stub(
    "mkdir -p \"$dir/etc\"\n"
    "printf 'VERSION=\"9.8\"\\n' > \"$dir/etc/os-release\"\n"
    "exit 0\n"
)
TAR_NO_OS_RELEASE = _tar_stub(
    "mkdir -p \"$dir/etc\" \"$dir/usr/lib\"\n"
    "exit 0\n"
)
TAR_HEALTHY = _tar_stub(
    "mkdir -p \"$dir/etc\" \"$dir/usr/lib\"\n"
    "printf 'VERSION=\"9.8\"\\n' > \"$dir/etc/os-release\"\n"
    "exit 0\n"
)
# tar may exit non-zero on benign warnings while still producing a usable tree.
TAR_HEALTHY_NONZERO = _tar_stub(
    "mkdir -p \"$dir/etc\" \"$dir/usr/lib\"\n"
    "printf 'VERSION=\"9.8\"\\n' > \"$dir/etc/os-release\"\n"
    "exit 2\n"
)


@pytest.fixture
def scan_env(tmp_path):
    pull_secret = tmp_path / "pull-secret.txt"
    pull_secret.write_text("{}")
    return {
        "PULL_SECRET": str(pull_secret),
        "RESULTS_DIR": str(tmp_path / "results"),
        "PROFILES": "xccdf_org.ssgproject.content_profile_e8",
    }


def _run(run_script, stub_binary, env, tar_body: str):
    stub_binary("oc", OC_STUB)
    stub_binary("podman", PODMAN_STUB)
    stub_binary("tar", tar_body)
    return run_script(SCRIPT, "4.22.0", env=env)


def test_empty_extraction_fails(run_script, stub_binary, scan_env):
    result = _run(run_script, stub_binary, scan_env, TAR_EMPTY)
    output = result.stdout + result.stderr
    assert result.returncode != 0, output
    assert "produced no usable tree" in output


def test_missing_usr_tree_fails(run_script, stub_binary, scan_env):
    result = _run(run_script, stub_binary, scan_env, TAR_NO_USR)
    output = result.stdout + result.stderr
    assert result.returncode != 0, output
    assert "produced no usable tree" in output


def test_missing_os_release_fails(run_script, stub_binary, scan_env):
    result = _run(run_script, stub_binary, scan_env, TAR_NO_OS_RELEASE)
    output = result.stdout + result.stderr
    assert result.returncode != 0, output
    assert "Could not determine RHCOS version" in output


def test_healthy_extraction_proceeds(run_script, stub_binary, scan_env):
    result = _run(run_script, stub_binary, scan_env, TAR_HEALTHY)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "RHCOS version: 9.8" in output
    assert "Scan complete" in output


def test_nonzero_tar_status_with_usable_tree_proceeds(
    run_script, stub_binary, scan_env
):
    result = _run(run_script, stub_binary, scan_env, TAR_HEALTHY_NONZERO)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "checking the result" in output
    assert "Scan complete" in output
