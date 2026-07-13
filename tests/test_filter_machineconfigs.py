#!/usr/bin/env python3
"""Tests for core/filter-machineconfig-flags.py"""
from __future__ import annotations

import os
import sys
import tempfile
import shutil
import urllib.parse
import pytest
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'core'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "filtmc", os.path.join(os.path.dirname(__file__), '..', 'core',
                           'filter-machineconfig-flags.py'))
filtmc = module_from_spec(spec)
spec.loader.exec_module(filtmc)


class TestParseConfigContent:
    def test_basic_decode(self):
        content = "PermitRootLogin no\nPasswordAuthentication no\n"
        encoded = "data:," + urllib.parse.quote(content, safe='')
        result = filtmc.parse_config_content(encoded)
        assert result == ["PermitRootLogin no", "PasswordAuthentication no"]

    def test_skips_empty_lines(self):
        content = "line1\n\nline2\n"
        encoded = "data:," + urllib.parse.quote(content, safe='')
        result = filtmc.parse_config_content(encoded)
        assert result == ["line1", "line2"]

    def test_invalid_prefix(self):
        with pytest.raises(ValueError, match="data:,"):
            filtmc.parse_config_content("https://example.com")


class TestFilterConfigLines:
    def test_basic_filter(self):
        lines = ["PermitRootLogin no", "PasswordAuthentication no", "X11Forwarding no"]
        result = filtmc.filter_config_lines(lines, {"PermitRootLogin"})
        assert result == ["PermitRootLogin no"]

    def test_case_insensitive(self):
        lines = ["PermitRootLogin no"]
        result = filtmc.filter_config_lines(lines, {"permitrootlogin"}, case_sensitive=False)
        assert result == ["PermitRootLogin no"]

    def test_case_sensitive(self):
        lines = ["PermitRootLogin no"]
        result = filtmc.filter_config_lines(lines, {"permitrootlogin"}, case_sensitive=True)
        assert result == []

    def test_skips_comments(self):
        lines = ["# PermitRootLogin yes", "PermitRootLogin no"]
        result = filtmc.filter_config_lines(lines, {"PermitRootLogin"})
        assert result == ["PermitRootLogin no"]

    def test_multiple_flags(self):
        lines = ["PermitRootLogin no", "PasswordAuthentication no", "X11Forwarding no"]
        result = filtmc.filter_config_lines(lines, {"PermitRootLogin", "X11Forwarding"})
        assert len(result) == 2
        assert "PermitRootLogin no" in result
        assert "X11Forwarding no" in result

    def test_no_matches(self):
        lines = ["PermitRootLogin no"]
        result = filtmc.filter_config_lines(lines, {"NonExistent"})
        assert result == []

    def test_empty_input(self):
        result = filtmc.filter_config_lines([], {"test"})
        assert result == []


class TestCreateFilteredMachineconfig:
    @pytest.fixture
    def tmpdir(self):
        d = tempfile.mkdtemp()
        yield d
        shutil.rmtree(d)

    def _write_mc(self, tmpdir, lines):
        content = "\n".join(lines) + "\n"
        encoded = urllib.parse.quote(content, safe='')
        mc = {
            "apiVersion": "machineconfiguration.openshift.io/v1",
            "kind": "MachineConfig",
            "spec": {
                "config": {
                    "ignition": {"version": "3.5.0"},
                    "storage": {
                        "files": [{
                            "path": "/etc/ssh/sshd_config",
                            "contents": {"source": f"data:,{encoded}"},
                            "mode": 384,
                            "overwrite": True,
                        }]
                    }
                }
            }
        }
        fpath = os.path.join(tmpdir, "input.yaml")
        with open(fpath, 'w') as f:
            yaml.dump(mc, f)
        return fpath

    def test_creates_filtered_output(self, tmpdir):
        input_file = self._write_mc(tmpdir, [
            "PermitRootLogin no",
            "PasswordAuthentication no",
            "X11Forwarding no",
        ])
        output_file = os.path.join(tmpdir, "output.yaml")
        filtmc.create_filtered_machineconfig(
            input_file, output_file, ["PermitRootLogin"])
        assert os.path.exists(output_file)
        with open(output_file) as f:
            content = f.read()
        assert "PermitRootLogin" in content
        assert "X11Forwarding" not in content

    def test_no_matching_flags(self, tmpdir, capsys):
        input_file = self._write_mc(tmpdir, ["PermitRootLogin no"])
        output_file = os.path.join(tmpdir, "output.yaml")
        filtmc.create_filtered_machineconfig(
            input_file, output_file, ["NonExistent"])
        assert not os.path.exists(output_file)
        captured = capsys.readouterr()
        assert "No matching flags" in captured.out

    def test_invalid_input(self, tmpdir):
        fpath = os.path.join(tmpdir, "bad.yaml")
        with open(fpath, 'w') as f:
            yaml.dump({"kind": "ConfigMap"}, f)
        with pytest.raises(ValueError, match="not a valid MachineConfig"):
            filtmc.create_filtered_machineconfig(
                fpath, os.path.join(tmpdir, "out.yaml"), ["test"])

    def test_description_header(self, tmpdir):
        input_file = self._write_mc(tmpdir, ["PermitRootLogin no"])
        output_file = os.path.join(tmpdir, "output.yaml")
        filtmc.create_filtered_machineconfig(
            input_file, output_file, ["PermitRootLogin"],
            description="Test description")
        with open(output_file) as f:
            first_line = f.readline()
        assert "Test description" in first_line
