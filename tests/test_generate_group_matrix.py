#!/usr/bin/env python3
"""Tests for scripts/generate-group-matrix.py tracking source of truth."""
from __future__ import annotations

import json
import os
import shutil
import tempfile
from typing import Any

import pytest

from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "generate_group_matrix",
    os.path.join(os.path.dirname(__file__), "..", "scripts",
                 "generate-group-matrix.py"))
matrix = module_from_spec(spec)
spec.loader.exec_module(matrix)


def write_json(directory: str, filename: str, data: Any) -> str:
    path = os.path.join(directory, filename)
    with open(path, "w") as f:
        json.dump(data, f)
    return path


def tracking(*pairs: tuple[str, str]) -> dict[str, Any]:
    """Build a tracking document from (check_name, group_id) pairs."""
    return {
        "remediations": {
            name: {"group": gid} for name, gid in pairs
        }
    }


def scan_export(passing=None, failing=None, manual=None) -> dict[str, Any]:
    return {
        "passing_checks": {
            "high": [{"check": n} for n in (passing or [])],
        },
        "remediations": {
            "high": [{"name": n} for n in (failing or [])],
        },
        "manual_checks": [{"check": n} for n in (manual or [])],
    }


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


class TestListVersionedTrackingFiles:
    def test_includes_versioned_files_only(self, tmpdir):
        write_json(tmpdir, "tracking-4_22.json", tracking(("a", "H1")))
        write_json(tmpdir, "tracking-5_0.json", tracking(("b", "H1")))
        write_json(tmpdir, "tracking.json", tracking(("ignored", "H1")))
        write_json(tmpdir, "tracking-4_22-20260101.json",
                   tracking(("snapshot", "H1")))
        names = [
            os.path.basename(p)
            for p in matrix.list_versioned_tracking_files(tmpdir)
        ]
        assert names == ["tracking-4_22.json", "tracking-5_0.json"]

    def test_empty_dir(self, tmpdir):
        assert matrix.list_versioned_tracking_files(tmpdir) == []

    def test_two_digit_major_version(self, tmpdir):
        write_json(tmpdir, "tracking-10_0.json", tracking(("a", "H1")))
        names = [
            os.path.basename(p)
            for p in matrix.list_versioned_tracking_files(tmpdir)
        ]
        assert names == ["tracking-10_0.json"]


class TestLatestTrackingFile:
    def test_picks_highest_numeric_version(self, tmpdir):
        older = write_json(tmpdir, "tracking-4_22.json", tracking(("a", "H1")))
        newer = write_json(tmpdir, "tracking-5_0.json", tracking(("b", "H1")))
        write_json(tmpdir, "tracking-4_21.json", tracking(("c", "H1")))
        chosen = matrix.latest_tracking_file(
            matrix.list_versioned_tracking_files(tmpdir)
        )
        assert chosen == newer
        assert chosen != older

    def test_two_digit_major_beats_single_digit(self, tmpdir):
        write_json(tmpdir, "tracking-5_0.json", tracking(("a", "H1")))
        newest = write_json(tmpdir, "tracking-10_0.json", tracking(("b", "H1")))
        chosen = matrix.latest_tracking_file(
            matrix.list_versioned_tracking_files(tmpdir)
        )
        assert chosen == newest
    def test_skips_timestamped_and_unversioned(self, tmpdir):
        write_json(tmpdir, "ocp-4_22.json", scan_export())
        write_json(tmpdir, "ocp-5_0.json", scan_export())
        write_json(tmpdir, "ocp-10_0.json", scan_export())
        write_json(tmpdir, "ocp-5_0-2026-01-01.json", scan_export())
        write_json(tmpdir, "group-matrix.json", {})
        names = [os.path.basename(p) for p in matrix.list_scan_files(tmpdir)]
        assert names == ["ocp-10_0.json", "ocp-4_22.json", "ocp-5_0.json"]


class TestCollectGroupChecks:
    def test_merges_checks_across_versions(self):
        docs = [
            tracking(("configure-crypto-policy", "H1")),
            tracking(
                ("configure-crypto-policy", "H1"),
                ("new-50-only-check", "H1"),
            ),
        ]
        result = matrix.collect_group_checks(docs)
        assert result["H1"] == {
            "configure-crypto-policy",
            "new-50-only-check",
        }

    def test_keeps_older_only_checks(self):
        docs = [
            tracking(("legacy-check", "M1"), ("shared-check", "M1")),
            tracking(("shared-check", "M1")),
        ]
        result = matrix.collect_group_checks(docs)
        assert result["M1"] == {"legacy-check", "shared-check"}

    def test_skips_empty_group_and_missing_remediations(self):
        docs = [
            {"remediations": {"orphan": {"group": ""}, "ok": {"group": "H2"}}},
            {},
        ]
        result = matrix.collect_group_checks(docs)
        assert result == {"H2": {"ok"}}

    def test_skips_null_group(self):
        docs = [tracking(("ok", "H1"))]
        docs[0]["remediations"]["null-group"] = {"group": None}
        result = matrix.collect_group_checks(docs)
        assert result == {"H1": {"ok"}}


class TestLoadExistingMatrix:
    def test_missing_file_returns_empty(self, tmpdir):
        assert matrix.load_existing_matrix(
            os.path.join(tmpdir, "group-matrix.json")
        ) == {}

    def test_reads_existing(self, tmpdir):
        path = write_json(tmpdir, "group-matrix.json", {"H1": {"note": "n"}})
        assert matrix.load_existing_matrix(path)["H1"]["note"] == "n"


class TestBuildMatrixSourceOfTruth:
    def test_five_oh_only_check_is_visible(self):
        group_checks = matrix.collect_group_checks([
            tracking(("shared-check", "H1"), ("new-50-only-check", "H1")),
        ])
        scans = {
            "4_22": scan_export(failing=["ocp4-moderate-shared-check"]),
            "5_0": scan_export(
                failing=[
                    "ocp4-moderate-shared-check",
                    "ocp4-moderate-new-50-only-check",
                ]
            ),
        }
        result = matrix.build_matrix(group_checks, scans, descriptions={})
        assert result["H1"]["4_22"]["total"] == 2
        assert result["H1"]["5_0"]["total"] == 2
        assert result["H1"]["5_0"]["fail"] == 2
        assert result["H1"]["4_22"]["fail"] == 1


class TestMain:
    def test_uses_latest_tracking_and_preserves_notes(self, tmpdir):
        write_json(tmpdir, "tracking.json",
                   tracking(("should-not-appear", "H1")))
        write_json(tmpdir, "tracking-4_22.json",
                   tracking(("legacy-only-check", "H1"),
                            ("shared-check", "H1")))
        write_json(tmpdir, "tracking-5_0.json",
                   tracking(("shared-check", "H1"),
                            ("new-50-only-check", "H1")))
        write_json(tmpdir, "ocp-4_22.json",
                   scan_export(failing=["shared-check"]))
        write_json(tmpdir, "ocp-5_0.json",
                   scan_export(failing=["shared-check", "new-50-only-check"]))
        write_json(tmpdir, "ocp-5_0-2026-01-01.json",
                   scan_export(failing=["timestamped-should-skip"]))
        write_json(tmpdir, "group-matrix.json",
                   {"H1": {"note": "keep me"}})

        matrix.main(tmpdir)

        with open(os.path.join(tmpdir, "group-matrix.json")) as f:
            out = json.load(f)
        assert "should-not-appear" not in str(out)
        assert out["H1"]["note"] == "keep me"
        assert out["H1"]["4_22"]["total"] == 2
        assert out["H1"]["5_0"]["fail"] == 2
        assert out["H1"]["4_22"]["fail"] == 1
        assert "5_0-2026-01-01" not in out["H1"]

    def test_exits_when_no_tracking_files(self, tmpdir):
        with pytest.raises(SystemExit, match="No versioned tracking"):
            matrix.main(tmpdir)
