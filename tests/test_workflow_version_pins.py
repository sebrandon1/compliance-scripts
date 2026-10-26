#!/usr/bin/env python3
"""Checks that rhcos-static-scan.yml takes image tags from versions.env (issue #424)."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOW = REPO / ".github" / "workflows" / "rhcos-static-scan.yml"


def test_workflow_has_no_hardcoded_version_literals():
    text = WORKFLOW.read_text()
    for literal in ("v0.1.81", "v1.9.0"):
        assert literal not in text, f"rhcos-static-scan.yml still pins {literal}"


def test_workflow_sources_versions_env():
    text = WORKFLOW.read_text()
    assert "source versions.env" in text


def test_scan_step_defaults_to_sourced_pins():
    text = WORKFLOW.read_text()
    assert "steps.pins.outputs.content_tag" in text
    assert text.count("steps.pins.outputs.co_tag") == 2


def test_tags_remain_overridable():
    text = WORKFLOW.read_text()
    for name in ("content_tag", "openscap_tag", "must_gather_tag"):
        assert f"inputs.{name} ||" in text, f"{name} input no longer overrides the pin"
