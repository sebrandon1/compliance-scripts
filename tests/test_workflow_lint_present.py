#!/usr/bin/env python3
"""Regression tests for the actionlint workflow lint (issue #445).

`make lint` once covered only Python and shell scripts; nothing validated
`.github/workflows/*.yml` or the bash embedded in `run:` blocks. These tests
keep the pinned actionlint job and the Makefile target wired up.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHELL_LINT = REPO / ".github" / "workflows" / "shell-lint.yml"
MAKEFILE = REPO / "Makefile"
SHELLCHECKRC = REPO / ".shellcheckrc"


def test_workflow_installs_pinned_actionlint():
    text = SHELL_LINT.read_text()
    match = re.search(r"ACTIONLINT_VERSION=(\d+\.\d+\.\d+)", text)
    assert match, "shell-lint.yml must pin an actionlint version"
    assert "releases/download/v${ACTIONLINT_VERSION}/" in text


def test_workflow_runs_actionlint():
    text = SHELL_LINT.read_text()
    assert "actionlint -color" in text, "shell-lint.yml must run actionlint"


def test_actionlint_job_is_present():
    text = SHELL_LINT.read_text()
    assert re.search(r"^  actionlint:\s*$", text, re.MULTILINE)


def test_makefile_has_workflow_lint_target():
    text = MAKEFILE.read_text()
    assert re.search(r"^workflow-lint:", text, re.MULTILINE)
    lint_target = re.search(r"^lint:.*$", text, re.MULTILINE)
    assert lint_target, "Makefile must define a lint target"
    assert "workflow-lint" in lint_target.group(0)


def test_shellcheckrc_single_source_of_exclusions():
    assert SHELLCHECKRC.exists(), ".shellcheckrc holds the shared exclusions"
    text = SHELLCHECKRC.read_text()
    match = re.search(r"^disable=(.+)$", text, re.MULTILINE)
    assert match, ".shellcheckrc must define disable="
    for code in ("SC1091", "SC2129", "SC2155"):
        assert code in match.group(1)


def test_workflow_does_not_duplicate_shellcheck_exclusions():
    """Exclusions live in .shellcheckrc, not repeated on every command line."""
    text = SHELL_LINT.read_text()
    assert "SC1091,SC2034" not in text


def test_actionlint_reads_exclusions_from_shellcheckrc():
    """The CI step must feed actionlint the same exclusions shellcheck uses."""
    text = SHELL_LINT.read_text()
    assert "sed -n 's/^disable=//p' .shellcheckrc" in text


def test_actionlint_job_installs_shellcheck():
    """Without shellcheck present, actionlint silently skips `run:` blocks."""
    text = SHELL_LINT.read_text()
    actionlint_job = text.split("  actionlint:", 1)[1]
    assert "install -y shellcheck" in actionlint_job


def test_shellcheck_find_is_null_safe():
    """SC2038: find output must be NUL-delimited before xargs."""
    text = SHELL_LINT.read_text()
    assert "-print0 | xargs -0 shellcheck" in text
