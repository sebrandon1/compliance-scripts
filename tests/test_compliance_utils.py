#!/usr/bin/env python3
"""Tests for lib/compliance_utils.py"""
from __future__ import annotations

import os
import sys
import tempfile

import pytest
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
import compliance_utils


class TestValidSeverities:
    def test_contains_expected_values(self):
        assert compliance_utils.VALID_SEVERITIES == {"high", "medium", "low"}

    def test_is_a_set(self):
        assert isinstance(compliance_utils.VALID_SEVERITIES, set)


class TestSafeShortname:
    def test_simple_path(self):
        assert compliance_utils.safe_shortname("/etc/sysctl.d/99-sysctl.conf") == "99-sysctl"

    def test_no_extension(self):
        assert compliance_utils.safe_shortname("/etc/sysctl.d/99-sysctl") == "99-sysctl"

    def test_audit_rules_path(self):
        assert compliance_utils.safe_shortname("/etc/audit/rules.d/75-dac-modification.rules") == "75-dac-modification"

    def test_basename_only(self):
        assert compliance_utils.safe_shortname("sshd_config") == "sshd_config"

    def test_special_chars_in_fallback(self):
        result = compliance_utils.safe_shortname("weird@file#name")
        assert result != ""

    def test_no_numeric_prefix(self):
        assert compliance_utils.safe_shortname("sshd.conf") == "sshd"

    def test_deep_path(self):
        result = compliance_utils.safe_shortname("/a/b/c/d/e/file.yaml")
        assert result == "file"

    def test_dotfile(self):
        result = compliance_utils.safe_shortname(".hidden")
        assert result != ""


class TestParseMachineConfigFiles:
    def _write_mc(self, directory: str, filename: str, path: str,
                  content: str, role: str = "worker") -> str:
        mc = {
            "apiVersion": "machineconfiguration.openshift.io/v1",
            "kind": "MachineConfig",
            "metadata": {
                "name": f"99-{filename.replace('.yaml', '')}",
                "labels": {
                    "machineconfiguration.openshift.io/role": role,
                },
            },
            "spec": {
                "config": {
                    "ignition": {"version": "3.5.0"},
                    "storage": {
                        "files": [{
                            "path": path,
                            "contents": {
                                "source": f"data:,{content}",
                            },
                        }],
                    },
                },
            },
        }
        fpath = os.path.join(directory, filename)
        with open(fpath, "w") as f:
            yaml.dump(mc, f)
        return fpath

    def test_single_file(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_mc(td, "test.yaml", "/etc/sysctl.d/99-test.conf",
                           "net.ipv4.ip_forward=1")
            files_map, skipped = compliance_utils.parse_machineconfig_files(td)
            assert len(files_map) == 1
            assert len(skipped) == 0
            key = ("/etc/sysctl.d/99-test.conf", None)
            assert key in files_map
            assert files_map[key][0]["lines"] == ["net.ipv4.ip_forward=1"]

    def test_severity_from_directory(self):
        with tempfile.TemporaryDirectory() as td:
            high_dir = os.path.join(td, "high")
            os.makedirs(high_dir)
            self._write_mc(high_dir, "test.yaml", "/etc/test.conf", "value=1")
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            key = ("/etc/test.conf", "high")
            assert key in files_map

    def test_multiple_files_same_path(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_mc(td, "a.yaml", "/etc/test.conf", "line1")
            self._write_mc(td, "b.yaml", "/etc/test.conf", "line2")
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            key = ("/etc/test.conf", None)
            assert len(files_map[key]) == 2

    def test_skips_non_yaml(self):
        with tempfile.TemporaryDirectory() as td:
            with open(os.path.join(td, "readme.txt"), "w") as f:
                f.write("not yaml")
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            assert len(files_map) == 0

    def test_skips_non_machineconfig(self):
        with tempfile.TemporaryDirectory() as td:
            fpath = os.path.join(td, "other.yaml")
            with open(fpath, "w") as f:
                yaml.dump({"kind": "ConfigMap", "metadata": {"name": "x"}}, f)
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            assert len(files_map) == 0

    def test_exclude_dirs(self):
        with tempfile.TemporaryDirectory() as td:
            excluded = os.path.join(td, "skip-me")
            os.makedirs(excluded)
            self._write_mc(excluded, "test.yaml", "/etc/test.conf", "value=1")
            files_map, _ = compliance_utils.parse_machineconfig_files(
                td, exclude_dirs={"skip-me"}
            )
            assert len(files_map) == 0

    def test_malformed_yaml_skipped(self):
        with tempfile.TemporaryDirectory() as td:
            fpath = os.path.join(td, "bad.yaml")
            with open(fpath, "w") as f:
                f.write("{{invalid yaml")
            files_map, skipped = compliance_utils.parse_machineconfig_files(td)
            assert len(files_map) == 0
            assert len(skipped) == 1

    def test_role_extraction(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_mc(td, "master.yaml", "/etc/test.conf",
                           "value=1", role="master")
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            key = ("/etc/test.conf", None)
            assert files_map[key][0]["role"] == "master"

    def test_default_role_is_worker(self):
        with tempfile.TemporaryDirectory() as td:
            mc = {
                "apiVersion": "machineconfiguration.openshift.io/v1",
                "kind": "MachineConfig",
                "metadata": {"name": "99-test"},
                "spec": {
                    "config": {
                        "ignition": {"version": "3.5.0"},
                        "storage": {
                            "files": [{
                                "path": "/etc/test.conf",
                                "contents": {"source": "data:,value=1"},
                            }],
                        },
                    },
                },
            }
            fpath = os.path.join(td, "test.yaml")
            with open(fpath, "w") as f:
                yaml.dump(mc, f)
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            key = ("/etc/test.conf", None)
            assert files_map[key][0]["role"] == "worker"

    def test_url_encoded_content(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_mc(td, "test.yaml", "/etc/test.conf",
                           "key%3Dvalue%20with%20spaces")
            files_map, _ = compliance_utils.parse_machineconfig_files(td)
            key = ("/etc/test.conf", None)
            assert files_map[key][0]["lines"] == ["key=value with spaces"]

    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as td:
            files_map, skipped = compliance_utils.parse_machineconfig_files(td)
            assert len(files_map) == 0
            assert len(skipped) == 0


class TestParseSeverityFilter:
    def test_none_returns_none(self):
        assert compliance_utils.parse_severity_filter(None) is None

    def test_empty_string_returns_none(self):
        assert compliance_utils.parse_severity_filter("") is None

    def test_single_severity(self):
        result = compliance_utils.parse_severity_filter("high")
        assert result == {"high"}

    def test_multiple_severities(self):
        result = compliance_utils.parse_severity_filter("high,medium")
        assert result == {"high", "medium"}

    def test_all_severities(self):
        result = compliance_utils.parse_severity_filter("high,medium,low")
        assert result == {"high", "medium", "low"}

    def test_case_insensitive(self):
        result = compliance_utils.parse_severity_filter("HIGH,Medium")
        assert result == {"high", "medium"}

    def test_whitespace_handled(self):
        result = compliance_utils.parse_severity_filter(" high , medium ")
        assert result == {"high", "medium"}

    def test_invalid_severity_exits(self):
        with pytest.raises(SystemExit) as exc:
            compliance_utils.parse_severity_filter("critical")
        assert "critical" in str(exc.value)

    def test_mixed_valid_and_invalid_exits(self):
        with pytest.raises(SystemExit) as exc:
            compliance_utils.parse_severity_filter("high,bogus")
        assert "bogus" in str(exc.value)

    def test_whitespace_only_returns_empty_set(self):
        result = compliance_utils.parse_severity_filter("   ")
        assert result == set() or result is None


class TestCheckVirtualenv:
    def test_warns_when_not_in_venv(self, capsys, monkeypatch):
        monkeypatch.delattr(sys, "real_prefix", raising=False)
        monkeypatch.setattr(sys, "base_prefix", sys.prefix)
        compliance_utils.check_virtualenv()
        captured = capsys.readouterr()
        assert "Warning" in captured.err

    def test_no_warning_with_real_prefix(self, capsys, monkeypatch):
        if not hasattr(sys, "real_prefix"):
            sys.real_prefix = "/some/path"
            try:
                compliance_utils.check_virtualenv()
            finally:
                del sys.real_prefix
        else:
            compliance_utils.check_virtualenv()
        captured = capsys.readouterr()
        assert "Warning" not in captured.err

    def test_no_warning_with_different_base_prefix(self, capsys, monkeypatch):
        monkeypatch.delattr(sys, "real_prefix", raising=False)
        monkeypatch.setattr(sys, "base_prefix", "/different/prefix")
        compliance_utils.check_virtualenv()
        captured = capsys.readouterr()
        assert "Warning" not in captured.err
