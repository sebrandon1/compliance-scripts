#!/usr/bin/env python3
"""Docs and make targets for Hardened-page helper scripts (issue #324)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _section(text: str, heading: str, next_heading: str) -> str:
    start = text.index(heading)
    end = text.index(next_heading, start + len(heading))
    return text[start:end]


def test_scripts_reference_covers_each_script_contract():
    text = (ROOT / "docs" / "scripts-reference.md").read_text()
    gen = _section(text, "**generate-group-matrix.py**", "**backfill-scan-profiles.py**")
    backfill = _section(
        text, "**backfill-scan-profiles.py**", "**rhcos-static-scan.sh**"
    )

    assert "There are no CLI flags" in gen
    assert "make generate-group-matrix" in gen
    assert "make export-compliance" in gen

    assert "There are no CLI flags" in backfill
    assert "make backfill-scan-profiles" in backfill
    assert "without `profiles`" in backfill
    assert "make export-compliance" in backfill


def test_make_targets_and_claude_list_both_commands():
    make_targets = (ROOT / "docs" / "make-targets.md").read_text()
    claude = (ROOT / "CLAUDE.md").read_text()
    for text in (make_targets, claude):
        assert "make generate-group-matrix" in text
        assert "make backfill-scan-profiles" in text
        assert "Fill missing per-profile counts" in text


def test_claude_md_says_update_dashboard_skips_helpers():
    text = (ROOT / "CLAUDE.md").read_text()
    assert "update-dashboard" in text
    assert "does not run these two scripts" in text


def test_makefile_defines_dashboard_targets():
    text = (ROOT / "Makefile").read_text()
    assert "\ngenerate-group-matrix:" in text
    assert "\nbackfill-scan-profiles:" in text
    assert "python3 scripts/generate-group-matrix.py" in text
    assert "python3 scripts/backfill-scan-profiles.py" in text


def test_helper_scripts_have_no_cli_flags():
    for name in ("generate-group-matrix.py", "backfill-scan-profiles.py"):
        src = (ROOT / "scripts" / name).read_text()
        assert "argparse" not in src
        assert 'if __name__ == "__main__":\n    main()' in src


def test_export_history_entry_omits_profiles():
    text = (ROOT / "core" / "export-compliance-data.sh").read_text()
    start = text.index("HISTORY_ENTRY=")
    end = text.index("if [[ -f \"$HISTORY_FILE\" ]]", start)
    assert "profiles" not in text[start:end]
