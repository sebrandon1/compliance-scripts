#!/usr/bin/env python3
"""Static checks for verify-remediation-group.yml (issue #441).

The workflow must fail when it applies no remediation objects, and it must not
depend on ``yq`` being installed on the runner. ``oc`` is guaranteed because the
job runs against a live quick-ocp cluster.
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOW = REPO / ".github" / "workflows" / "verify-remediation-group.yml"


def test_workflow_does_not_invoke_yq() -> None:
    text = WORKFLOW.read_text()
    assert "yq e " not in text, "verify-remediation-group.yml must not depend on yq"
    assert "$(yq " not in text, "verify-remediation-group.yml must not depend on yq"


def test_workflow_fails_when_nothing_was_applied() -> None:
    text = WORKFLOW.read_text()
    assert 'if [ "$APPLIED" -eq 0 ]' in text
    assert "Applied 0 remediation objects" in text


def test_workflow_fails_when_no_file_can_be_classified() -> None:
    text = WORKFLOW.read_text()
    assert 'if [ "$SKIPPED" -eq "$TOTAL" ]' in text
    assert "Could not classify any of the" in text


def test_workflow_classifies_kinds_with_oc() -> None:
    text = WORKFLOW.read_text()
    assert "oc apply --dry-run=client -o jsonpath='{.kind}'" in text
