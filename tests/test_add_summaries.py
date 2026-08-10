#!/usr/bin/env python3
"""Tests for core/add-summaries.py"""
from __future__ import annotations

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'core'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "add_summaries",
    os.path.join(os.path.dirname(__file__), '..', 'core', 'add-summaries.py'))
add_summaries = module_from_spec(spec)
spec.loader.exec_module(add_summaries)


class TestGenerateSummary:
    """Tests for the generate_summary function."""

    def test_empty_description_returns_empty(self):
        assert add_summaries.generate_summary("some-check", "") == ""

    def test_crypto_policy(self):
        result = add_summaries.generate_summary(
            "configure-crypto-policy", "Set the crypto policy")
        assert "crypto" in result.lower()

    def test_empty_passwords(self):
        result = add_summaries.generate_summary(
            "no-empty-password", "Prevent empty passwords")
        assert "nullok" in result.lower() or "pam" in result.lower()

    def test_encryption_provider(self):
        result = add_summaries.generate_summary(
            "encryption-provider-config", "Configure encryption")
        assert "aescbc" in result.lower()

    def test_kubeadmin_removed(self):
        result = add_summaries.generate_summary(
            "kubeadmin-removed", "Remove kubeadmin user")
        assert "kubeadmin" in result.lower()

    def test_sshd_disable_root(self):
        result = add_summaries.generate_summary(
            "sshd-disable-root-login", "Disable root SSH login")
        assert "PermitRootLogin" in result

    def test_sshd_generic_catchall(self):
        result = add_summaries.generate_summary(
            "sshd-some-unknown-setting", "Configure SSH")
        assert "sshd_config" in result.lower()

    def test_sysctl_specific(self):
        result = add_summaries.generate_summary(
            "sysctl-kernel-dmesg-restrict", "Restrict dmesg")
        assert "kernel.dmesg_restrict" in result

    def test_sysctl_generic_catchall(self):
        result = add_summaries.generate_summary(
            "sysctl-net-some-unknown-param", "Set network param")
        assert "net.some.unknown.param" in result

    def test_sysctl_bare_name(self):
        result = add_summaries.generate_summary(
            "sysctl", "Configure sysctl")
        assert "sysctl" in result.lower()

    def test_network_policy_by_name(self):
        result = add_summaries.generate_summary(
            "network-policies-configured", "Ensure network policies")
        assert "NetworkPolicy" in result

    def test_network_policy_by_description(self):
        result = add_summaries.generate_summary(
            "some-check", "Ensure each namespace has a NetworkPolicy")
        assert "NetworkPolicy" in result

    def test_audit_rules_dac_chmod(self):
        result = add_summaries.generate_summary(
            "audit-rules-dac-modification-chmod", "Audit chmod")
        assert "chmod" in result

    def test_audit_rules_generic(self):
        result = add_summaries.generate_summary(
            "audit-rules-some-new-rule", "Add audit rule")
        assert "audit" in result.lower()

    def test_rbac_cluster_admin(self):
        result = add_summaries.generate_summary(
            "rbac-limit-cluster-admin", "Limit cluster-admin usage")
        assert "cluster-admin" in result

    def test_rbac_generic(self):
        result = add_summaries.generate_summary(
            "rbac-something-else", "Configure RBAC")
        assert "RBAC" in result

    def test_scc_limit_root(self):
        result = add_summaries.generate_summary(
            "scc-limit-root-containers", "Prevent root containers")
        assert "root" in result.lower()

    def test_scc_generic(self):
        result = add_summaries.generate_summary(
            "scc-some-new-setting", "Configure SCC")
        assert "SCC" in result or "SecurityContextConstraints" in result

    def test_coredump_disable(self):
        result = add_summaries.generate_summary(
            "coredump-disable-backtraces", "Disable coredumps")
        assert "coredump" in result.lower()

    def test_file_permissions(self):
        result = add_summaries.generate_summary(
            "file-permissions-etc-shadow", "Set shadow permissions")
        assert "permissions" in result.lower()

    def test_service_account_tokens(self):
        result = add_summaries.generate_summary(
            "service-account-tokens", "Disable token automount")
        assert "automountServiceAccountToken" in result

    def test_machineconfig_fallback(self):
        result = add_summaries.generate_summary(
            "unknown-check-xyz",
            "To remediate this, create a MachineConfig object and apply it")
        assert "MachineConfig" in result

    def test_set_description_fallback(self):
        result = add_summaries.generate_summary(
            "unknown-check-xyz",
            "Set max_log_file to 8 in auditd.conf")
        assert "max_log_file" in result

    def test_generic_fallback(self):
        result = add_summaries.generate_summary(
            "totally-unknown-check",
            "This is some vague description without actionable keywords")
        assert result == "Review and apply recommended configuration"

    # Pattern ordering tests
    def test_allowed_registries_for_import_before_allowed_registries(self):
        import_result = add_summaries.generate_summary(
            "allowed-registries-for-import", "Set import registries")
        generic_result = add_summaries.generate_summary(
            "allowed-registries", "Set allowed registries")
        assert "allowedRegistriesForImport" in import_result
        assert "allowedRegistries" in generic_result
        assert import_result != generic_result

    def test_sshd_specific_before_generic(self):
        specific = add_summaries.generate_summary(
            "sshd-disable-root-login", "Disable root login in SSH")
        generic = add_summaries.generate_summary(
            "sshd-new-future-setting", "Configure new SSH setting")
        assert "PermitRootLogin" in specific
        assert "sshd_config" in generic

    def test_audit_rules_specific_before_generic(self):
        specific = add_summaries.generate_summary(
            "audit-rules-dac-modification-chmod", "Audit chmod")
        generic = add_summaries.generate_summary(
            "audit-rules-brand-new", "New audit rule")
        assert "chmod" in specific
        assert "audit" in generic.lower()


class TestProcessChecks:
    """Tests for the process_checks function."""

    def test_adds_summary_to_check(self):
        checks = [{"name": "sshd-disable-root-login",
                   "description": "Disable root SSH login"}]
        count = add_summaries.process_checks(checks)
        assert count == 1
        assert "PermitRootLogin" in checks[0]["summary"]

    def test_skips_existing_summary(self):
        checks = [{"name": "sshd-disable-root-login",
                   "description": "Disable root SSH login",
                   "summary": "existing summary"}]
        count = add_summaries.process_checks(checks)
        assert count == 0
        assert checks[0]["summary"] == "existing summary"

    def test_counts_multiple(self):
        checks = [
            {"name": "crypto-policy", "description": "Set crypto policy"},
            {"name": "kubeadmin-removed", "description": "Remove kubeadmin"},
        ]
        count = add_summaries.process_checks(checks)
        assert count == 2

    def test_empty_list(self):
        count = add_summaries.process_checks([])
        assert count == 0

    def test_no_description_skipped(self):
        checks = [{"name": "test-check", "description": ""}]
        count = add_summaries.process_checks(checks)
        assert count == 0

    def test_missing_name_handled(self):
        checks = [{"description": "Some description of a setting"}]
        count = add_summaries.process_checks(checks)
        assert count == 1


class TestMain:
    """Tests for the main function (CLI integration)."""

    def test_enriches_json_file(self):
        data = {
            "version": "5.0",
            "scan_date": "2026-01-01T00:00:00Z",
            "summary": {"total_checks": 2, "passing": 0,
                         "failing": 2, "manual": 0},
            "remediations": {
                "high": [
                    {"name": "configure-crypto-policy",
                     "description": "Set the system crypto policy",
                     "status": "FAIL", "severity": "high"},
                ],
                "medium": [
                    {"name": "sshd-disable-root-login",
                     "description": "Disable root SSH",
                     "status": "FAIL", "severity": "medium"},
                ],
                "low": [],
            },
            "passing_checks": {"high": [], "medium": [], "low": []},
            "manual_checks": [],
        }

        with tempfile.TemporaryDirectory() as td:
            json_path = os.path.join(td, "test.json")
            with open(json_path, "w") as f:
                json.dump(data, f)

            old_argv = sys.argv
            try:
                sys.argv = ["prog", json_path]
                add_summaries.main()
            finally:
                sys.argv = old_argv

            with open(json_path) as f:
                result = json.load(f)

            assert "summary" in result["remediations"]["high"][0]
            assert "summary" in result["remediations"]["medium"][0]
            assert "crypto" in result["remediations"]["high"][0]["summary"].lower()
            assert "PermitRootLogin" in result["remediations"]["medium"][0]["summary"]

    def test_preserves_existing_summaries(self):
        data = {
            "version": "5.0",
            "scan_date": "2026-01-01T00:00:00Z",
            "summary": {"total_checks": 1, "passing": 0,
                         "failing": 1, "manual": 0},
            "remediations": {
                "high": [
                    {"name": "test-check",
                     "description": "Something",
                     "status": "FAIL", "severity": "high",
                     "summary": "Do not overwrite"},
                ],
                "medium": [], "low": [],
            },
            "passing_checks": {"high": [], "medium": [], "low": []},
            "manual_checks": [],
        }

        with tempfile.TemporaryDirectory() as td:
            json_path = os.path.join(td, "test.json")
            with open(json_path, "w") as f:
                json.dump(data, f)

            old_argv = sys.argv
            try:
                sys.argv = ["prog", json_path]
                add_summaries.main()
            finally:
                sys.argv = old_argv

            with open(json_path) as f:
                result = json.load(f)

            assert result["remediations"]["high"][0]["summary"] == "Do not overwrite"


class TestSummaryPatterns:
    """Verify representative patterns from each category produce expected results."""

    def test_all_patterns_have_non_empty_summary(self):
        for pattern, expected_summary in add_summaries.SUMMARY_PATTERNS:
            result = add_summaries.generate_summary(
                f"test-{pattern}-check", "Some description")
            assert result, f"Pattern '{pattern}' produced empty summary"

    def test_no_pattern_returns_generic_fallback(self):
        for pattern, expected_summary in add_summaries.SUMMARY_PATTERNS:
            result = add_summaries.generate_summary(
                f"test-{pattern}-check", "Some description")
            assert result != "Review and apply recommended configuration", (
                f"Pattern '{pattern}' fell through to generic fallback"
            )
