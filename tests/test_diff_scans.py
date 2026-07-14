#!/usr/bin/env python3
"""Tests for scripts/diff-scans.py"""
from __future__ import annotations

import os
import sys
from typing import Any

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "diff_scans", os.path.join(os.path.dirname(__file__), '..', 'scripts',
                               'diff-scans.py'))
diff_scans = module_from_spec(spec)
spec.loader.exec_module(diff_scans)


def make_export(
    checks: list[tuple[str, str, str, str]],
    version: str = "4.22",
    scan_date: str = "2026-01-01T00:00:00Z",
) -> dict[str, Any]:
    """Build a minimal scan export from a list of (name, status, severity, platform) tuples."""
    data = {
        "version": version,
        "scan_date": scan_date,
        "summary": {"total_checks": 0, "passing": 0, "failing": 0, "manual": 0, "skipped": 0},
        "remediations": {"high": [], "medium": [], "low": []},
        "passing_checks": {"high": [], "medium": [], "low": []},
        "manual_checks": [],
    }
    for name, status, severity, platform in checks:
        entry = {"name": name, "check": name, "status": status,
                 "description": "", "severity": severity, "platform": platform, "profile": ""}
        if status == "FAIL":
            data["remediations"][severity].append(entry)
            data["summary"]["failing"] += 1
        elif status == "PASS":
            data["passing_checks"][severity].append(entry)
            data["summary"]["passing"] += 1
        elif status == "MANUAL":
            data["manual_checks"].append(entry)
            data["summary"]["manual"] += 1
        data["summary"]["total_checks"] += 1
    return data


class TestBuildCheckMap:
    def test_maps_all_statuses(self):
        data = make_export([
            ("check-a", "PASS", "high", "ocp"),
            ("check-b", "FAIL", "medium", "rhcos"),
            ("check-c", "MANUAL", "low", "ocp"),
        ])
        result = diff_scans.build_check_map(data)
        assert len(result) == 3
        assert result["check-a"]["status"] == "PASS"
        assert result["check-b"]["status"] == "FAIL"
        assert result["check-c"]["status"] == "MANUAL"

    def test_empty_export(self):
        data = make_export([])
        result = diff_scans.build_check_map(data)
        assert len(result) == 0


class TestDiffScans:
    def test_no_changes(self):
        data = make_export([("check-a", "PASS", "high", "ocp")])
        result = diff_scans.diff_scans(data, data)
        assert len(result["pass_to_fail"]) == 0
        assert len(result["fail_to_pass"]) == 0
        assert len(result["added"]) == 0
        assert len(result["removed"]) == 0

    def test_regression(self):
        old = make_export([("check-a", "PASS", "high", "ocp")])
        new = make_export([("check-a", "FAIL", "high", "ocp")])
        result = diff_scans.diff_scans(old, new)
        assert len(result["pass_to_fail"]) == 1
        assert result["pass_to_fail"][0]["name"] == "check-a"

    def test_fix(self):
        old = make_export([("check-a", "FAIL", "high", "ocp")])
        new = make_export([("check-a", "PASS", "high", "ocp")])
        result = diff_scans.diff_scans(old, new)
        assert len(result["fail_to_pass"]) == 1
        assert result["fail_to_pass"][0]["name"] == "check-a"

    def test_new_check(self):
        old = make_export([("check-a", "PASS", "high", "ocp")])
        new = make_export([
            ("check-a", "PASS", "high", "ocp"),
            ("check-b", "FAIL", "medium", "rhcos"),
        ])
        result = diff_scans.diff_scans(old, new)
        assert len(result["added"]) == 1
        assert result["added"][0]["name"] == "check-b"

    def test_removed_check(self):
        old = make_export([
            ("check-a", "PASS", "high", "ocp"),
            ("check-b", "FAIL", "medium", "rhcos"),
        ])
        new = make_export([("check-a", "PASS", "high", "ocp")])
        result = diff_scans.diff_scans(old, new)
        assert len(result["removed"]) == 1
        assert result["removed"][0]["name"] == "check-b"

    def test_manual_status_change(self):
        old = make_export([("check-a", "MANUAL", "high", "ocp")])
        new = make_export([("check-a", "PASS", "high", "ocp")])
        result = diff_scans.diff_scans(old, new)
        assert len(result["manual_changes"]) == 1

    def test_mixed_changes(self):
        old = make_export([
            ("stays-pass", "PASS", "high", "ocp"),
            ("regresses", "PASS", "medium", "rhcos"),
            ("gets-fixed", "FAIL", "low", "ocp"),
            ("gets-removed", "FAIL", "medium", "rhcos"),
        ])
        new = make_export([
            ("stays-pass", "PASS", "high", "ocp"),
            ("regresses", "FAIL", "medium", "rhcos"),
            ("gets-fixed", "PASS", "low", "ocp"),
            ("brand-new", "PASS", "high", "ocp"),
        ])
        result = diff_scans.diff_scans(old, new)
        assert len(result["pass_to_fail"]) == 1
        assert len(result["fail_to_pass"]) == 1
        assert len(result["added"]) == 1
        assert len(result["removed"]) == 1

    def test_summary_preserved(self):
        old = make_export([("a", "PASS", "high", "ocp")], version="4.21")
        new = make_export([("a", "PASS", "high", "ocp")], version="4.22")
        result = diff_scans.diff_scans(old, new)
        assert result["old"]["version"] == "4.21"
        assert result["new"]["version"] == "4.22"

    def test_platform_in_regressions(self):
        old = make_export([("ocp-check", "PASS", "high", "ocp")])
        new = make_export([("ocp-check", "FAIL", "high", "ocp")])
        result = diff_scans.diff_scans(old, new)
        assert result["pass_to_fail"][0]["platform"] == "ocp"
