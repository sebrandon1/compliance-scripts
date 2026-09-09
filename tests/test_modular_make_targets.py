#!/usr/bin/env python3
"""Contract tests for the modular Makefile workflow."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_makefile_exposes_modular_create_and_validate_targets():
    text = (ROOT / "Makefile").read_text()

    assert "create-modular-configs:" in text
    assert "validate-modular-configs:" in text
    assert "./modular/create-modular-configs.sh" in text
    assert "./scripts/validate-machineconfig.sh -d" in text


def test_modular_make_targets_share_workflow_variables_and_dry_run():
    text = (ROOT / "Makefile").read_text()

    for variable in (
        "MODULAR_SOURCE",
        "MODULAR_OUTPUT",
        "MODULAR_SEVERITY",
        "MODULAR_DRY_RUN",
    ):
        assert variable in text
    assert "--dry-run" in text


def test_modular_docs_describe_make_targets():
    docs = (ROOT / "model-context" / "MODULAR_APPROACH.md").read_text()

    assert "make create-modular-configs" in docs
    assert "make validate-modular-configs" in docs
    assert "DRY_RUN=true" in docs
