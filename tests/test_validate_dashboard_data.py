#!/usr/bin/env python3
"""Tests for scripts/validate-dashboard-data.py"""

import json
import os
import sys
import tempfile
import shutil

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "validate_dashboard",
    os.path.join(os.path.dirname(__file__), '..', 'scripts',
                 'validate-dashboard-data.py'))
validate_dashboard = module_from_spec(spec)
spec.loader.exec_module(validate_dashboard)


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


def write_json(directory, filename, data):
    """Write a JSON file into a directory and return the path."""
    filepath = os.path.join(directory, filename)
    with open(filepath, 'w') as f:
        json.dump(data, f)
    return filepath


def make_valid_scan_export():
    """Build a minimal valid scan export."""
    return {
        "version": "4.22",
        "scan_date": "2026-01-01T00:00:00Z",
        "summary": {
            "total_checks": 10,
            "passing": 7,
            "failing": 2,
            "manual": 1,
        },
        "remediations": {
            "high": [{"name": "check-a", "status": "FAIL", "severity": "high"}],
            "medium": [{"name": "check-b", "status": "FAIL", "severity": "medium"}],
            "low": [],
        },
    }


def make_valid_tracking():
    """Build a minimal valid tracking.json."""
    return {
        "meta": {"version": "4.22"},
        "groups": {
            "H1": {
                "title": "Crypto Policy",
                "severity": "HIGH",
                "priority": 1,
                "status": "pass",
                "platform": "rhcos",
            },
            "M1": {
                "title": "SSHD Config",
                "severity": "MEDIUM",
                "priority": 2,
                "status": "pass-vanilla",
                "platform": "rhcos",
            },
        },
        "remediations": {
            "rhcos4-crypto-policy": {"group": "H1"},
            "rhcos4-sshd-config": {"group": "M1"},
        },
    }


def make_valid_scan_history():
    """Build a minimal valid scan-history.json."""
    return [
        {
            "version": "4.21",
            "scan_date": "2025-12-01T00:00:00Z",
            "summary": {
                "total_checks": 100,
                "passing": 80,
                "failing": 15,
                "manual": 5,
            },
        },
    ]


# --- validate_scan_export ---


class TestValidateScanExport:
    def test_valid_data_passes(self, tmpdir):
        fp = write_json(tmpdir, "ocp-4_22.json", make_valid_scan_export())
        errors = validate_dashboard.validate_scan_export(fp)
        assert errors == []

    def test_missing_top_level_keys(self, tmpdir):
        fp = write_json(tmpdir, "ocp-4_22.json", {"version": "4.22"})
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("Missing top-level keys" in e for e in errors)

    def test_missing_summary_fields(self, tmpdir):
        data = make_valid_scan_export()
        data["summary"] = {"total_checks": 10}
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("Missing summary fields" in e for e in errors)

    def test_summary_field_wrong_type(self, tmpdir):
        data = make_valid_scan_export()
        # Use a float to trigger the "must be int" check. A string would
        # crash the downstream sum computation (TypeError), but a float
        # is still summable so the rest of the validation runs cleanly.
        data["summary"]["passing"] = 7.5
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("must be int" in e for e in errors)

    def test_summary_counts_mismatch(self, tmpdir):
        data = make_valid_scan_export()
        data["summary"]["total_checks"] = 999
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("don't add up" in e for e in errors)

    def test_summary_counts_with_skipped(self, tmpdir):
        data = make_valid_scan_export()
        data["summary"]["skipped"] = 3
        data["summary"]["total_checks"] = 13
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert errors == []

    def test_remediations_not_a_list(self, tmpdir):
        data = make_valid_scan_export()
        data["remediations"]["high"] = "not-a-list"
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("must be a list" in e for e in errors)

    def test_remediation_item_missing_fields(self, tmpdir):
        data = make_valid_scan_export()
        data["remediations"]["high"] = [{"name": "check-a"}]
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("missing" in e for e in errors)

    def test_empty_remediations_valid(self, tmpdir):
        data = make_valid_scan_export()
        data["remediations"] = {"high": [], "medium": [], "low": []}
        data["summary"]["total_checks"] = 0
        data["summary"]["passing"] = 0
        data["summary"]["failing"] = 0
        data["summary"]["manual"] = 0
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert errors == []

    def test_passing_checks_valid(self, tmpdir):
        data = make_valid_scan_export()
        data["passing_checks"] = {
            "high": [{"name": "check-x"}],
            "medium": [],
            "low": [],
        }
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert errors == []

    def test_passing_checks_wrong_type(self, tmpdir):
        data = make_valid_scan_export()
        data["passing_checks"] = "not-a-dict"
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("must be a dict" in e for e in errors)

    def test_passing_checks_severity_not_list(self, tmpdir):
        data = make_valid_scan_export()
        data["passing_checks"] = {"high": "not-a-list", "medium": [], "low": []}
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("passing_checks.high must be a list" in e for e in errors)

    def test_passing_checks_item_missing_name(self, tmpdir):
        data = make_valid_scan_export()
        data["passing_checks"] = {"high": [{"status": "PASS"}], "medium": [], "low": []}
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("missing 'name'" in e for e in errors)

    def test_manual_checks_valid(self, tmpdir):
        data = make_valid_scan_export()
        data["manual_checks"] = [{"name": "manual-check-1"}]
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert errors == []

    def test_manual_checks_wrong_type(self, tmpdir):
        data = make_valid_scan_export()
        data["manual_checks"] = "not-a-list"
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("must be a list" in e for e in errors)

    def test_manual_checks_item_missing_name(self, tmpdir):
        data = make_valid_scan_export()
        data["manual_checks"] = [{"status": "MANUAL"}]
        fp = write_json(tmpdir, "ocp-4_22.json", data)
        errors = validate_dashboard.validate_scan_export(fp)
        assert any("missing 'name'" in e for e in errors)


# --- validate_tracking ---


class TestValidateTracking:
    def test_valid_data_passes(self, tmpdir):
        fp = write_json(tmpdir, "tracking.json", make_valid_tracking())
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_missing_top_level_keys(self, tmpdir):
        fp = write_json(tmpdir, "tracking.json", {"meta": {}})
        errors = validate_dashboard.validate_tracking(fp)
        assert any("Missing top-level keys" in e for e in errors)

    def test_groups_not_a_dict(self, tmpdir):
        data = make_valid_tracking()
        data["groups"] = []
        # Remove remediations so the validator doesn't crash trying to
        # call .keys() on the non-dict groups when cross-referencing.
        del data["remediations"]
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("must be a dict" in e for e in errors)

    def test_group_missing_required_fields(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"] = {"title": "Crypto Policy"}
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("missing fields" in e for e in errors)

    def test_group_invalid_severity(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["severity"] = "CRITICAL"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid severity" in e for e in errors)

    def test_group_invalid_platform(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["platform"] = "windows"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid platform" in e for e in errors)

    def test_remediations_not_a_dict(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"] = []
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("must be a dict" in e for e in errors)

    def test_remediation_missing_group(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["orphan-check"] = {"status": "FAIL"}
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("missing 'group'" in e for e in errors)

    def test_remediation_references_unknown_group(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["bad-ref"] = {"group": "NONEXISTENT"}
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("unknown group" in e for e in errors)

    def test_empty_groups_and_remediations(self, tmpdir):
        data = {"meta": {}, "groups": {}, "remediations": {}}
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_all_valid_platforms(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["platform"] = "ocp"
        data["groups"]["M1"]["platform"] = "mixed"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_all_valid_severities(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["severity"] = "LOW"
        data["groups"]["M1"]["severity"] = "MANUAL"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []


# --- validate_scan_history ---


class TestValidateScanHistory:
    def test_valid_data_passes(self, tmpdir):
        fp = write_json(tmpdir, "scan-history.json", make_valid_scan_history())
        errors = validate_dashboard.validate_scan_history(fp)
        assert errors == []

    def test_not_an_array(self, tmpdir):
        fp = write_json(tmpdir, "scan-history.json", {"not": "an array"})
        errors = validate_dashboard.validate_scan_history(fp)
        assert any("must be a JSON array" in e for e in errors)

    def test_empty_array_valid(self, tmpdir):
        fp = write_json(tmpdir, "scan-history.json", [])
        errors = validate_dashboard.validate_scan_history(fp)
        assert errors == []

    def test_entry_not_an_object(self, tmpdir):
        fp = write_json(tmpdir, "scan-history.json", ["not-an-object"])
        errors = validate_dashboard.validate_scan_history(fp)
        assert any("must be an object" in e for e in errors)

    def test_entry_missing_fields(self, tmpdir):
        fp = write_json(tmpdir, "scan-history.json", [{"version": "4.22"}])
        errors = validate_dashboard.validate_scan_history(fp)
        assert any("missing fields" in e for e in errors)

    def test_summary_field_wrong_type(self, tmpdir):
        entry = make_valid_scan_history()[0]
        entry["summary"]["passing"] = "eighty"
        fp = write_json(tmpdir, "scan-history.json", [entry])
        errors = validate_dashboard.validate_scan_history(fp)
        assert any("must be int" in e for e in errors)

    def test_multiple_entries(self, tmpdir):
        entries = make_valid_scan_history()
        entries.append({
            "version": "4.23",
            "scan_date": "2026-06-01T00:00:00Z",
            "summary": {
                "total_checks": 110,
                "passing": 90,
                "failing": 12,
                "manual": 8,
            },
        })
        fp = write_json(tmpdir, "scan-history.json", entries)
        errors = validate_dashboard.validate_scan_history(fp)
        assert errors == []


# --- main() integration ---


class TestMainIntegration:
    def test_main_with_valid_data(self, tmpdir):
        write_json(tmpdir, "ocp-4_22.json", make_valid_scan_export())
        write_json(tmpdir, "tracking.json", make_valid_tracking())
        write_json(tmpdir, "scan-history.json", make_valid_scan_history())

        old_argv = sys.argv
        try:
            sys.argv = ["validate-dashboard-data.py", tmpdir]
            validate_dashboard.main()
        finally:
            sys.argv = old_argv

    def test_main_with_invalid_data_exits(self, tmpdir):
        write_json(tmpdir, "ocp-4_22.json", {"version": "4.22"})

        old_argv = sys.argv
        try:
            sys.argv = ["validate-dashboard-data.py", tmpdir]
            with pytest.raises(SystemExit) as exc_info:
                validate_dashboard.main()
            assert exc_info.value.code == 1
        finally:
            sys.argv = old_argv

    def test_main_missing_directory_exits(self):
        old_argv = sys.argv
        try:
            sys.argv = ["validate-dashboard-data.py", "/nonexistent/path"]
            with pytest.raises(SystemExit) as exc_info:
                validate_dashboard.main()
            assert exc_info.value.code == 1
        finally:
            sys.argv = old_argv

    def test_main_skips_baseline_files(self, tmpdir):
        write_json(tmpdir, "ocp-4_22.json", make_valid_scan_export())
        write_json(tmpdir, "ocp-4_22-baseline.json", {"junk": True})

        old_argv = sys.argv
        try:
            sys.argv = ["validate-dashboard-data.py", tmpdir]
            validate_dashboard.main()
        finally:
            sys.argv = old_argv
