#!/usr/bin/env python3
"""Tests for scripts/validate-dashboard-data.py"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import shutil
from typing import Any

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


def write_json(directory: str, filename: str, data: Any) -> str:
    """Write a JSON file into a directory and return the path."""
    filepath = os.path.join(directory, filename)
    with open(filepath, 'w') as f:
        json.dump(data, f)
    return filepath


def make_valid_scan_export() -> dict[str, Any]:
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


def make_valid_tracking() -> dict[str, Any]:
    """Build a minimal valid tracking.json."""
    return {
        "meta": {"version": "4.22"},
        "groups": {
            "H1": {
                "title": "Crypto Policy",
                "severity": "HIGH",
                "priority": 1,
                "priority_label": "Critical",
                "status": "verified",
                "platform": "rhcos",
                "jira": "CNF-21212",
                "pr": "735",
                "compare": "compliance/4.22/h1-crypto-policy",
                "jira_status": "In Progress",
                "pr_state": "open",
                "prev_group": None,
                "next_group": "M1",
                "last_sync": "2026-05-05",
                "status_note": "Verified on cnfdt16.",
                "upstream_verdict": "ran-only",
            },
            "M1": {
                "title": "SSHD Config",
                "severity": "MEDIUM",
                "priority": 2,
                "priority_label": "High",
                "status": "pass-vanilla",
                "platform": "rhcos",
                "jira": "CNF-22620",
                "pr": None,
                "compare": None,
                "jira_status": "In Progress",
                "pr_state": None,
                "prev_group": "H1",
                "next_group": None,
                "last_sync": None,
                "status_note": "PASS on vanilla RHCOS 9.8.",
                "upstream_verdict": "pass-vanilla",
            },
        },
        "remediations": {
            "rhcos4-crypto-policy": {"group": "H1"},
            "rhcos4-sshd-config": {"group": "M1"},
        },
    }


def make_valid_scan_history() -> list[dict[str, Any]]:
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

    def test_invalid_group_id_format(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["INVALID"] = data["groups"].pop("H1")
        data["remediations"]["rhcos4-crypto-policy"]["group"] = "INVALID"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid group ID format" in e for e in errors)

    def test_valid_group_id_formats(self, tmpdir):
        data = make_valid_tracking()
        # Add groups with all valid prefixes
        base = {
            "title": "Test", "severity": "LOW", "priority": 4,
            "status": "pending", "platform": "rhcos",
            "prev_group": None, "next_group": None,
        }
        data["groups"]["L1"] = dict(base)
        data["groups"]["MAN1"] = dict(base, severity="MANUAL")
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_invalid_status(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["status"] = "unknown-status"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid status" in e for e in errors)

    def test_valid_status_values(self, tmpdir):
        """All known status values should pass."""
        data = make_valid_tracking()
        for status in ["verified", "verified-needed", "partial",
                       "pending", "not-applicable", "pass-vanilla",
                       "pass-vanilla-rhcos9.8"]:
            data["groups"]["H1"]["status"] = status
            fp = write_json(tmpdir, "tracking.json", data)
            errors = validate_dashboard.validate_tracking(fp)
            status_errors = [e for e in errors if "invalid status" in e]
            assert status_errors == [], f"status '{status}' should be valid"

    def test_priority_must_be_int(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["priority"] = "high"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("priority must be int" in e for e in errors)

    def test_invalid_priority_label(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["priority_label"] = "Urgent"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid priority_label" in e for e in errors)

    def test_all_valid_priority_labels(self, tmpdir):
        data = make_valid_tracking()
        for label in ["Critical", "High", "Medium", "Low"]:
            data["groups"]["H1"]["priority_label"] = label
            fp = write_json(tmpdir, "tracking.json", data)
            errors = validate_dashboard.validate_tracking(fp)
            label_errors = [
                e for e in errors if "invalid priority_label" in e
            ]
            assert label_errors == [], f"priority_label '{label}' valid"

    def test_invalid_pr_state(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["pr_state"] = "draft"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid pr_state" in e for e in errors)

    def test_valid_pr_states(self, tmpdir):
        data = make_valid_tracking()
        for state in ["open", "closed", "merged", None]:
            data["groups"]["H1"]["pr_state"] = state
            fp = write_json(tmpdir, "tracking.json", data)
            errors = validate_dashboard.validate_tracking(fp)
            state_errors = [
                e for e in errors if "invalid pr_state" in e
            ]
            assert state_errors == [], f"pr_state '{state}' should be valid"

    def test_prev_group_references_unknown(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["prev_group"] = "NONEXISTENT"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("prev_group references unknown" in e for e in errors)

    def test_next_group_references_unknown(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["next_group"] = "NONEXISTENT"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("next_group references unknown" in e for e in errors)

    def test_invalid_upstream_verdict(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["upstream_verdict"] = "maybe"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("invalid upstream_verdict" in e for e in errors)

    def test_valid_upstream_verdicts(self, tmpdir):
        data = make_valid_tracking()
        for verdict in ["upstream-candidate", "upstream-pr-exists",
                        "ran-only", "pass-vanilla", "platform-config",
                        "site-specific", "not-applicable", None]:
            data["groups"]["H1"]["upstream_verdict"] = verdict
            fp = write_json(tmpdir, "tracking.json", data)
            errors = validate_dashboard.validate_tracking(fp)
            verdict_errors = [
                e for e in errors if "invalid upstream_verdict" in e
            ]
            assert verdict_errors == [], \
                f"upstream_verdict '{verdict}' should be valid"

    def test_upstream_must_be_list(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["upstream"] = "not-a-list"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("upstream must be a list" in e for e in errors)

    def test_upstream_entries_must_be_objects(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["upstream"] = ["not-an-object"]
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("upstream[0] must be an object" in e for e in errors)

    def test_upstream_valid_list(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["upstream"] = [
            {"setting": "test", "repo": "test/repo"}
        ]
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert not any("upstream" in e for e in errors)

    def test_pr_can_be_string_or_int(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["pr"] = 735
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        pr_errors = [e for e in errors if "pr must be" in e]
        assert pr_errors == []

    def test_pr_wrong_type(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["pr"] = ["not", "valid"]
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("pr must be string, int, or null" in e for e in errors)

    def test_string_field_wrong_type(self, tmpdir):
        data = make_valid_tracking()
        data["groups"]["H1"]["jira"] = 12345
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("jira must be string or null" in e for e in errors)

    def test_remediation_not_an_object(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["bad-rem"] = "not-an-object"
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("must be an object" in e for e in errors)

    def test_remediation_optional_string_fields(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["rhcos4-crypto-policy"] = {
            "group": "H1",
            "description": "A check",
            "file": "/etc/crypto-policy",
            "certsuite": "some-test",
        }
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_remediation_field_wrong_type(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["rhcos4-crypto-policy"] = {
            "group": "H1",
            "description": 42,
        }
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("description must be string or null" in e for e in errors)

    def test_remediation_certsuite_as_list(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["rhcos4-crypto-policy"] = {
            "group": "H1",
            "certsuite": [
                {"id": "test-1", "suite": "networking"},
            ],
        }
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert errors == []

    def test_remediation_certsuite_list_bad_entry(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["rhcos4-crypto-policy"] = {
            "group": "H1",
            "certsuite": ["not-an-object"],
        }
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("certsuite[0] must be an object" in e for e in errors)

    def test_remediation_certsuite_wrong_type(self, tmpdir):
        data = make_valid_tracking()
        data["remediations"]["rhcos4-crypto-policy"] = {
            "group": "H1",
            "certsuite": 42,
        }
        fp = write_json(tmpdir, "tracking.json", data)
        errors = validate_dashboard.validate_tracking(fp)
        assert any("certsuite must be string, list, or null" in e
                   for e in errors)

    def test_minimal_group_still_valid(self, tmpdir):
        """Groups with only required fields should pass."""
        data = {
            "meta": {},
            "groups": {
                "H1": {
                    "title": "Test",
                    "severity": "HIGH",
                    "priority": 1,
                    "status": "pending",
                    "platform": "rhcos",
                },
            },
            "remediations": {},
        }
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
