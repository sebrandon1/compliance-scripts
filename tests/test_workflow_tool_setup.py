#!/usr/bin/env python3
"""Static checks that workflows install the CLI tools their steps invoke.

GitHub-hosted runners do not ship every tool a workflow uses. A missing
binary is easy to miss because call sites are often guarded with ``||`` or
``if``, so a failed lookup silently changes control flow instead of failing
the step. These tests keep tool installation next to the usage.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = REPO / ".github" / "workflows"

SKOPEO_INSTALL = "install -y -qq skopeo"


def _workflows() -> dict[str, str]:
    return {
        path.name: path.read_text()
        for path in sorted(WORKFLOW_DIR.glob("*.yml"))
    }


def _job_blocks(text: str) -> dict[str, str]:
    """Split a workflow into top-level job blocks keyed by job id.

    Job ids are the two-space-indented keys directly under ``jobs:``.
    """
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == "jobs:")
    except StopIteration:
        return {}

    blocks: dict[str, list[str]] = {}
    current: str | None = None
    for line in lines[start + 1:]:
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if match:
            current = match.group(1)
            blocks[current] = []
            continue
        if current is not None:
            blocks[current].append(line)
    return {name: "\n".join(body) for name, body in blocks.items()}


def test_workflows_using_skopeo_install_it() -> None:
    for name, text in _workflows().items():
        if "skopeo " not in text:
            continue
        assert SKOPEO_INSTALL in text, f"{name} invokes skopeo without installing it"


def test_each_job_installs_skopeo_before_using_it() -> None:
    for name, text in _workflows().items():
        for job, body in _job_blocks(text).items():
            usage = body.find("skopeo ")
            if usage == -1:
                continue
            install = body.find(SKOPEO_INSTALL)
            assert install != -1, f"{name}:{job} uses skopeo without installing it"
            assert install < usage, (
                f"{name}:{job} must install skopeo before the first use"
            )
