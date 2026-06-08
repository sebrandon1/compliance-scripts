#!/usr/bin/env python3
"""Tests for core/combine-machineconfigs-by-path.py"""

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
    "combine", os.path.join(os.path.dirname(__file__), '..', 'core',
                            'combine-machineconfigs-by-path.py'))
combine = module_from_spec(spec)
spec.loader.exec_module(combine)


def make_mc_yaml(path, lines, name="test-mc"):
    encoded = urllib.parse.quote("\n".join(lines) + "\n", safe='')
    return {
        "apiVersion": "machineconfiguration.openshift.io/v1",
        "kind": "MachineConfig",
        "metadata": {"name": name},
        "spec": {
            "config": {
                "ignition": {"version": "3.5.0"},
                "storage": {
                    "files": [{
                        "path": path,
                        "contents": {"source": f"data:,{encoded}"},
                        "mode": 384,
                        "overwrite": True,
                    }]
                }
            }
        }
    }


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


class TestSafeShortname:
    def test_simple_path(self):
        assert combine.safe_shortname("/etc/sysctl.d/99-compliance.conf") == "99-compliance"

    def test_audit_path(self):
        assert combine.safe_shortname("/etc/audit/rules.d/75-dac-modification.rules") == "75-dac-modification"

    def test_special_chars(self):
        result = combine.safe_shortname("/etc/ssh/sshd_config.d/50-hardening.conf")
        assert "50-hardening" == result

    def test_no_extension(self):
        result = combine.safe_shortname("/etc/securetty")
        assert result == "securetty"


class TestParseMachineConfigFiles:
    def test_single_file(self, tmpdir):
        mc = make_mc_yaml("/etc/sysctl.d/99-test.conf", ["net.ipv4.ip_forward=1"])
        fpath = os.path.join(tmpdir, "test.yaml")
        with open(fpath, 'w') as f:
            yaml.dump(mc, f)

        result = combine.parse_machineconfig_files(tmpdir)
        assert len(result) == 1
        key = list(result.keys())[0]
        assert key[0] == "/etc/sysctl.d/99-test.conf"
        assert len(result[key]) == 1
        assert result[key][0][1] == ["net.ipv4.ip_forward=1"]

    def test_severity_from_directory(self, tmpdir):
        high_dir = os.path.join(tmpdir, "high")
        os.makedirs(high_dir)
        mc = make_mc_yaml("/etc/sysctl.d/99-test.conf", ["kernel.dmesg_restrict=1"])
        with open(os.path.join(high_dir, "test.yaml"), 'w') as f:
            yaml.dump(mc, f)

        result = combine.parse_machineconfig_files(tmpdir)
        key = list(result.keys())[0]
        assert key[1] == "high"

    def test_multiple_files_same_path(self, tmpdir):
        mc1 = make_mc_yaml("/etc/sysctl.d/99-test.conf", ["net.ipv4.ip_forward=1"], "mc1")
        mc2 = make_mc_yaml("/etc/sysctl.d/99-test.conf", ["kernel.dmesg_restrict=1"], "mc2")
        with open(os.path.join(tmpdir, "mc1.yaml"), 'w') as f:
            yaml.dump(mc1, f)
        with open(os.path.join(tmpdir, "mc2.yaml"), 'w') as f:
            yaml.dump(mc2, f)

        result = combine.parse_machineconfig_files(tmpdir)
        assert len(result) == 1
        key = list(result.keys())[0]
        assert len(result[key]) == 2

    def test_skips_non_machineconfig(self, tmpdir):
        doc = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "test"}}
        with open(os.path.join(tmpdir, "configmap.yaml"), 'w') as f:
            yaml.dump(doc, f)

        result = combine.parse_machineconfig_files(tmpdir)
        assert len(result) == 0

    def test_skips_non_yaml(self, tmpdir):
        with open(os.path.join(tmpdir, "readme.txt"), 'w') as f:
            f.write("not a yaml file")

        result = combine.parse_machineconfig_files(tmpdir)
        assert len(result) == 0

    def test_skips_combo_dir(self, tmpdir):
        combo_dir = os.path.join(tmpdir, "combo")
        os.makedirs(combo_dir)
        mc = make_mc_yaml("/etc/test.conf", ["test=1"])
        with open(os.path.join(combo_dir, "test.yaml"), 'w') as f:
            yaml.dump(mc, f)

        result = combine.parse_machineconfig_files(tmpdir)
        assert len(result) == 0


class TestWriteComboYaml:
    def test_basic_output(self, tmpdir):
        sources = [("file1.yaml", ["line1", "line2"]), ("file2.yaml", ["line2", "line3"])]
        combine.write_combo_yaml("/etc/test.conf", "high", sources, tmpdir, "none")

        outfile = os.path.join(tmpdir, "test-high-combo.yaml")
        assert os.path.exists(outfile)

        with open(outfile) as f:
            doc = yaml.safe_load(f)
        assert doc["kind"] == "MachineConfig"
        assert doc["spec"]["config"]["ignition"]["version"] == "3.5.0"

    def test_deduplication(self, tmpdir):
        sources = [("f1.yaml", ["aaa", "bbb"]), ("f2.yaml", ["bbb", "ccc"])]
        combine.write_combo_yaml("/etc/test.conf", None, sources, tmpdir, "none")

        outfile = os.path.join(tmpdir, "test-combo.yaml")
        with open(outfile) as f:
            content = f.read()
        source_line = [line for line in content.split('\n') if 'source: data:,' in line][0]
        encoded = source_line.split('data:,')[1]
        decoded = urllib.parse.unquote(encoded)
        lines = [line for line in decoded.strip().split('\n') if line]
        assert len(lines) == 3
        assert sorted(lines) == ["aaa", "bbb", "ccc"]

    def test_no_severity_in_filename(self, tmpdir):
        sources = [("f1.yaml", ["test"])]
        combine.write_combo_yaml("/etc/test.conf", None, sources, tmpdir, "none")
        assert os.path.exists(os.path.join(tmpdir, "test-combo.yaml"))

    def test_provenance_header(self, tmpdir):
        sources = [("f1.yaml", ["test"])]
        combine.write_combo_yaml("/etc/test.conf", "high", sources, tmpdir, "provenance")
        with open(os.path.join(tmpdir, "test-high-combo.yaml")) as f:
            first_line = f.readline()
        assert "Combined from" in first_line


class TestMoveOriginals:
    def test_moves_combined_files(self, tmpdir):
        combo_dir = os.path.join(tmpdir, "combo")
        os.makedirs(combo_dir)
        with open(os.path.join(tmpdir, "f1.yaml"), 'w') as f:
            f.write("test")
        with open(os.path.join(tmpdir, "f2.yaml"), 'w') as f:
            f.write("test")

        combo_map = {("/etc/test.conf", None): [("f1.yaml", ["a"]), ("f2.yaml", ["b"])]}
        combine.move_originals_to_combo(combo_map, tmpdir, combo_dir)

        assert not os.path.exists(os.path.join(tmpdir, "f1.yaml"))
        assert os.path.exists(os.path.join(combo_dir, "f1.yaml"))

    def test_skips_single_source(self, tmpdir):
        combo_dir = os.path.join(tmpdir, "combo")
        os.makedirs(combo_dir)
        with open(os.path.join(tmpdir, "f1.yaml"), 'w') as f:
            f.write("test")

        combo_map = {("/etc/test.conf", None): [("f1.yaml", ["a"])]}
        combine.move_originals_to_combo(combo_map, tmpdir, combo_dir)

        assert os.path.exists(os.path.join(tmpdir, "f1.yaml"))
