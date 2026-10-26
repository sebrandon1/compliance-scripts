"""Shared fixtures for behavioral tests of shell scripts.

The scripts under test shell out to `oc`, `skopeo`, `curl`, `gh`, and friends.
Networked or cluster-touching calls are replaced by executable stubs placed at
the front of PATH, so the tests stay hermetic and fast.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

# Ambient values that would make a test depend on the developer's shell.
_ISOLATED_VARS = ("GH_TOKEN", "GITHUB_TOKEN", "GITHUB_ACTIONS", "CURL_STATUS", "LOG_LEVEL")


@pytest.fixture
def stub_dir(tmp_path):
    """The private bin directory that holds the stubs for one test."""
    path = tmp_path / "stub-bin"
    path.mkdir(exist_ok=True)
    return path


@pytest.fixture
def stub_binary(stub_dir):
    """Return a callable that installs an executable stub in stub_dir."""

    def _stub(name: str, body: str) -> Path:
        path = stub_dir / name
        path.write_text(body)
        path.chmod(0o755)
        return path

    return _stub


@pytest.fixture
def run_script(stub_dir):
    """Return a callable that runs a repo script with stub_dir prefixed to PATH."""

    def _run(script: Path, *args, env: dict[str, str] | None = None,
             cwd: Path | None = None) -> subprocess.CompletedProcess:
        full_env = os.environ.copy()
        for name in _ISOLATED_VARS:
            full_env.pop(name, None)
        if env:
            full_env.update(env)
        full_env["PATH"] = f"{stub_dir}{os.pathsep}{full_env['PATH']}"
        return subprocess.run(
            [str(script), *[str(arg) for arg in args]],
            capture_output=True,
            text=True,
            env=full_env,
            cwd=cwd,
        )

    return _run
