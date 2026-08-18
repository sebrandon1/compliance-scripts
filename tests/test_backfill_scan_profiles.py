#!/usr/bin/env python3
"""Tests for scripts/backfill-scan-profiles.py."""
from __future__ import annotations

import json
import os
import shutil
import tempfile
from typing import Any

import pytest
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "backfill_scan_profiles",
    os.path.join(os.path.dirname(__file__), "..", "scripts",
                 "backfill-scan-profiles.py"))
backfill = module_from_spec(spec)
spec.loader.exec_module(backfill)


def write_json(directory: str, filename: str, data: Any) -> str:
    path = os.path.join(directory, filename)
    with open(path, "w") as f:
        json.dump(data, f)
    return path


def scan_export(passing=None, failing=None, manual=None) -> dict[str, Any]:
    def items(pairs):
        return [{"profile": profile} for profile in (pairs or [])]

    return {
        "passing_checks": {"high": items(passing)},
        "remediations": {"medium": items(failing)},
        "manual_checks": items(manual),
    }


def history_entry(version="5.0", scan_date="2026-06-04T19:01:51Z",
                  profiles=None) -> dict[str, Any]:
    return {"version": version, "scan_date": scan_date, "profiles": profiles}


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


class TestProfilesFromScan:
    def test_aggregates_pass_fail_manual_by_profile(self):
        scan = scan_export(
            passing=["E8", "E8", "CIS"],
            failing=["E8", "Moderate"],
            manual=["CIS"],
        )
        result = backfill.profiles_from_scan(scan)
        assert result == {
            "CIS": {"passing": 1, "failing": 0, "manual": 1},
            "E8": {"passing": 2, "failing": 1, "manual": 0},
            "Moderate": {"passing": 0, "failing": 1, "manual": 0},
        }

    def test_skips_empty_profiles_and_returns_none_when_none_found(self):
        scan = scan_export(passing=[""], failing=[None])
        scan["passing_checks"]["high"].append({})
        assert backfill.profiles_from_scan(scan) is None
        assert backfill.profiles_from_scan({}) is None


class TestComputeProfiles:
    def test_reads_scan_file(self, tmpdir):
        path = write_json(
            tmpdir, "ocp-5_0.json",
            scan_export(passing=["E8"], failing=["CIS"]),
        )
        result = backfill.compute_profiles(path)
        assert result["E8"]["passing"] == 1
        assert result["CIS"]["failing"] == 1


class TestFindScanFile:
    def test_prefers_dated_over_baseline_and_latest(self, tmpdir):
        dated = write_json(tmpdir, "ocp-5_0-2026-06-04.json", {})
        write_json(tmpdir, "ocp-5_0-baseline-2026-06-04.json", {})
        write_json(tmpdir, "ocp-5_0.json", {})
        chosen = backfill.find_scan_file(
            history_entry("5.0", "2026-06-04T19:01:51Z"), tmpdir
        )
        assert chosen == dated

    def test_falls_back_to_dated_baseline(self, tmpdir):
        baseline = write_json(
            tmpdir, "ocp-4_22-baseline-2026-05-05.json", {}
        )
        write_json(tmpdir, "ocp-4_22.json", {})
        chosen = backfill.find_scan_file(
            history_entry("4.22", "2026-05-05T13:09:41Z"), tmpdir
        )
        assert chosen == baseline

    def test_falls_back_to_latest_undated_file(self, tmpdir):
        latest = write_json(tmpdir, "ocp-4_21.json", {})
        chosen = backfill.find_scan_file(
            history_entry("4.21", "2026-01-14T20:19:36Z"), tmpdir
        )
        assert chosen == latest

    def test_returns_none_when_no_candidates(self, tmpdir):
        assert backfill.find_scan_file(
            history_entry("5.0", "2026-06-04T00:00:00Z"), tmpdir
        ) is None


class TestBackfillHistory:
    def test_fills_missing_profiles_from_dated_scan(self, tmpdir):
        write_json(
            tmpdir, "ocp-5_0-2026-06-04.json",
            scan_export(passing=["E8"]),
        )
        write_json(
            tmpdir, "ocp-5_0.json",
            scan_export(passing=["CIS"]),
        )
        history = [history_entry(profiles=None)]
        updated = backfill.backfill_history(history, tmpdir)
        assert updated == 1
        assert history[0]["profiles"] == {
            "E8": {"passing": 1, "failing": 0, "manual": 0},
        }

    def test_noop_when_profiles_already_exist(self, tmpdir):
        write_json(
            tmpdir, "ocp-5_0.json",
            scan_export(passing=["E8"]),
        )
        existing = {
            "CIS": {"passing": 9, "failing": 1, "manual": 0},
        }
        history = [history_entry(profiles=existing)]
        updated = backfill.backfill_history(history, tmpdir)
        assert updated == 0
        assert history[0]["profiles"] is existing

    def test_retries_null_profiles(self, tmpdir):
        write_json(tmpdir, "ocp-5_0.json", scan_export(passing=["E8"]))
        history = [history_entry(profiles=None)]
        updated = backfill.backfill_history(history, tmpdir)
        assert updated == 1
        assert history[0]["profiles"]["E8"]["passing"] == 1

    def test_sets_none_when_no_scan_file(self, tmpdir):
        history = [{"version": "5.0", "scan_date": "2026-06-04T00:00:00Z"}]
        updated = backfill.backfill_history(history, tmpdir)
        assert updated == 0
        assert history[0]["profiles"] is None


class TestMain:
    def test_writes_history_and_skips_existing(self, tmpdir):
        write_json(tmpdir, "ocp-5_0.json", scan_export(passing=["E8"]))
        existing = {"CIS": {"passing": 1, "failing": 0, "manual": 0}}
        write_json(tmpdir, "scan-history.json", [
            history_entry(profiles=None),
            history_entry(profiles=existing),
        ])
        backfill.main(tmpdir)
        with open(os.path.join(tmpdir, "scan-history.json")) as f:
            out = json.load(f)
        assert out[0]["profiles"]["E8"]["passing"] == 1
        assert out[1]["profiles"] == existing
