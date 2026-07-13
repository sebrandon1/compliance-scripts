#!/usr/bin/env python3
"""Tests for modular/split-machineconfigs-modular.py"""

import os
import sys
import tempfile
import shutil
import urllib.parse

import pytest
import yaml

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), '..', 'modular'))
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location(
    "split_modular",
    os.path.join(os.path.dirname(__file__), '..', 'modular',
                 'split-machineconfigs-modular.py'))
split_mod = module_from_spec(spec)
spec.loader.exec_module(split_mod)


def make_mc_yaml(path, lines, name="test-mc", role="worker"):
    """Build a MachineConfig dict with a single file entry."""
    encoded = urllib.parse.quote("\n".join(lines) + "\n", safe='')
    return {
        "apiVersion": "machineconfiguration.openshift.io/v1",
        "kind": "MachineConfig",
        "metadata": {
            "name": name,
            "labels": {
                "machineconfiguration.openshift.io/role": role
            }
        },
        "spec": {
            "config": {
                "ignition": {"version": "3.5.0"},
                "storage": {
                    "files": [{
                        "path": path,
                        "contents": {"source": f"data:,{encoded}"},
                        "mode": 0o644,
                        "overwrite": True,
                    }]
                }
            }
        }
    }


def make_mc_yaml_systemd(units, name="test-mc", role="worker"):
    """Build a MachineConfig dict with systemd units (no storage files)."""
    return {
        "apiVersion": "machineconfiguration.openshift.io/v1",
        "kind": "MachineConfig",
        "metadata": {
            "name": name,
            "labels": {
                "machineconfiguration.openshift.io/role": role
            }
        },
        "spec": {
            "config": {
                "ignition": {"version": "3.5.0"},
                "systemd": {
                    "units": units
                }
            }
        }
    }


def make_mc_yaml_kernelargs(kargs, name="test-mc", role="worker"):
    """Build a MachineConfig with kernel arguments only."""
    return {
        "apiVersion": "machineconfiguration.openshift.io/v1",
        "kind": "MachineConfig",
        "metadata": {
            "name": name,
            "labels": {
                "machineconfiguration.openshift.io/role": role
            }
        },
        "spec": {
            "config": {
                "ignition": {"version": "3.5.0"},
            },
            "kernelArguments": kargs
        }
    }


@pytest.fixture
def tmpdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


@pytest.fixture
def outdir():
    d = tempfile.mkdtemp()
    yield d
    shutil.rmtree(d)


# ---- safe_shortname ----

class TestSafeShortname:
    def test_simple_path(self):
        assert split_mod.safe_shortname(
            "/etc/ssh/sshd_config") == "sshd_config"

    def test_numbered_prefix(self):
        result = split_mod.safe_shortname(
            "/etc/sysctl.d/99-compliance.conf")
        assert result == "99-compliance"

    def test_no_extension(self):
        assert split_mod.safe_shortname("/etc/securetty") == "securetty"

    def test_dot_d_conf(self):
        result = split_mod.safe_shortname(
            "/etc/ssh/sshd_config.d/50-hardening.conf")
        assert result == "50-hardening"

    def test_audit_rules(self):
        result = split_mod.safe_shortname(
            "/etc/audit/rules.d/75-dac.rules")
        assert result == "75-dac"

    def test_special_characters_cleaned(self):
        # Path without extension and with underscores/dashes preserved
        result = split_mod.safe_shortname("/etc/pam.d/system-auth")
        assert result == "system-auth"


# ---- extract_meaningful_settings ----

class TestExtractMeaningfulSettings:
    def test_filters_comments(self):
        lines = [
            "# This is a comment",
            "PermitRootLogin no",
            "  # Another comment",
            "PasswordAuthentication no",
        ]
        result = split_mod.extract_meaningful_settings(lines)
        assert result == ["PermitRootLogin no", "PasswordAuthentication no"]

    def test_filters_empty_lines(self):
        lines = ["", "   ", "PermitRootLogin no", ""]
        result = split_mod.extract_meaningful_settings(lines)
        assert result == ["PermitRootLogin no"]

    def test_filters_include_directives(self):
        lines = [
            "Include /etc/ssh/sshd_config.d/*.conf",
            "PermitRootLogin no",
        ]
        result = split_mod.extract_meaningful_settings(lines)
        assert result == ["PermitRootLogin no"]

    def test_filters_pam_include(self):
        lines = [
            "@include system-auth.d/*",
            "auth required pam_unix.so",
        ]
        result = split_mod.extract_meaningful_settings(lines)
        assert result == ["auth required pam_unix.so"]

    def test_empty_input(self):
        assert split_mod.extract_meaningful_settings([]) == []

    def test_all_comments(self):
        lines = ["# comment1", "# comment2"]
        assert split_mod.extract_meaningful_settings(lines) == []

    def test_preserves_inline_content(self):
        lines = ["key = value  # inline note"]
        # The function keeps lines that don't START with #
        result = split_mod.extract_meaningful_settings(lines)
        assert result == ["key = value  # inline note"]


# ---- parse_machineconfig_files ----

class TestParseMachineConfigFiles:
    def test_single_file(self, tmpdir):
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"])
        with open(os.path.join(tmpdir, "sshd.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(skipped) == 0
        assert len(files_map) == 1
        key = list(files_map.keys())[0]
        assert key[0] == "/etc/ssh/sshd_config"
        assert key[1] is None  # no severity subdir
        assert files_map[key][0]['lines'] == ["PermitRootLogin no"]

    def test_severity_from_directory(self, tmpdir):
        high_dir = os.path.join(tmpdir, "high")
        os.makedirs(high_dir)
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitEmptyPasswords no"])
        with open(os.path.join(high_dir, "h2.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert key[1] == "high"

    def test_medium_severity(self, tmpdir):
        med_dir = os.path.join(tmpdir, "medium")
        os.makedirs(med_dir)
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["ClientAliveInterval 300"])
        with open(os.path.join(med_dir, "m1.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert key[1] == "medium"

    def test_role_extracted_from_labels(self, tmpdir):
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"],
            role="master")
        with open(os.path.join(tmpdir, "master-mc.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert files_map[key][0]['role'] == "master"

    def test_defaults_to_worker(self, tmpdir):
        # MC without role label should default to worker
        mc = {
            "apiVersion": "machineconfiguration.openshift.io/v1",
            "kind": "MachineConfig",
            "metadata": {"name": "no-role-mc"},
            "spec": {
                "config": {
                    "ignition": {"version": "3.5.0"},
                    "storage": {
                        "files": [{
                            "path": "/etc/test.conf",
                            "contents": {
                                "source": "data:,test%3D1%0A"
                            },
                            "mode": 0o644,
                            "overwrite": True,
                        }]
                    }
                }
            }
        }
        with open(os.path.join(tmpdir, "norole.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert files_map[key][0]['role'] == "worker"

    def test_multiple_files_same_path(self, tmpdir):
        mc1 = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"], name="mc1")
        mc2 = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PasswordAuthentication no"], name="mc2")
        with open(os.path.join(tmpdir, "mc1.yaml"), 'w') as f:
            yaml.dump(mc1, f)
        with open(os.path.join(tmpdir, "mc2.yaml"), 'w') as f:
            yaml.dump(mc2, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 1
        key = list(files_map.keys())[0]
        assert len(files_map[key]) == 2

    def test_skips_non_yaml_files(self, tmpdir):
        with open(os.path.join(tmpdir, "readme.txt"), 'w') as f:
            f.write("not yaml")

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0

    def test_skips_non_machineconfig(self, tmpdir):
        doc = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {"name": "test"}
        }
        with open(os.path.join(tmpdir, "cm.yaml"), 'w') as f:
            yaml.dump(doc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0

    def test_malformed_yaml_reported(self, tmpdir):
        with open(os.path.join(tmpdir, "bad.yaml"), 'w') as f:
            f.write("{{{invalid")

        _, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(skipped) == 1
        assert "bad.yaml" in skipped[0][0]

    def test_empty_config_no_files(self, tmpdir):
        mc = {
            "apiVersion": "machineconfiguration.openshift.io/v1",
            "kind": "MachineConfig",
            "metadata": {"name": "empty-mc"},
            "spec": {
                "config": {
                    "ignition": {"version": "3.5.0"}
                }
            }
        }
        with open(os.path.join(tmpdir, "empty.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0
        assert len(skipped) == 0

    def test_systemd_only_mc_ignored(self, tmpdir):
        """MCs with only systemd units (no storage files) produce no entries."""
        mc = make_mc_yaml_systemd(
            [{"name": "test.service", "enabled": True}])
        with open(os.path.join(tmpdir, "systemd.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0
        assert len(skipped) == 0

    def test_kernelargs_only_mc_ignored(self, tmpdir):
        """MCs with kernel arguments but no storage files produce
        no file entries."""
        mc = make_mc_yaml_kernelargs(["nosmt", "audit=1"])
        with open(os.path.join(tmpdir, "kargs.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0
        assert len(skipped) == 0

    def test_empty_directory(self, tmpdir):
        files_map, skipped = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 0
        assert len(skipped) == 0

    def test_nested_severity_dirs(self, tmpdir):
        nested = os.path.join(tmpdir, "remediations", "low", "sshd")
        os.makedirs(nested)
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["Banner /etc/issue"])
        with open(os.path.join(nested, "banner.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert key[1] == "low"

    def test_source_file_relative_path(self, tmpdir):
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"])
        with open(os.path.join(tmpdir, "test.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert files_map[key][0]['source_file'] == "test.yaml"

    def test_basename_stored(self, tmpdir):
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"])
        with open(os.path.join(tmpdir, "my-rem.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        assert files_map[key][0]['basename'] == "my-rem.yaml"

    def test_url_encoded_content_decoded(self, tmpdir):
        """Verify URL-encoded content in source field is properly decoded."""
        # Manually write a file with URL-encoded content
        encoded = urllib.parse.quote(
            "PermitRootLogin no\nBanner /etc/issue\n", safe='')
        mc = {
            "apiVersion": "machineconfiguration.openshift.io/v1",
            "kind": "MachineConfig",
            "metadata": {
                "name": "encoded-mc",
                "labels": {
                    "machineconfiguration.openshift.io/role": "worker"
                }
            },
            "spec": {
                "config": {
                    "ignition": {"version": "3.5.0"},
                    "storage": {
                        "files": [{
                            "path": "/etc/ssh/sshd_config",
                            "contents": {
                                "source": f"data:,{encoded}"
                            },
                            "mode": 0o644,
                            "overwrite": True,
                        }]
                    }
                }
            }
        }
        with open(os.path.join(tmpdir, "encoded.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        lines = files_map[key][0]['lines']
        assert "PermitRootLogin no" in lines
        assert "Banner /etc/issue" in lines


# ---- generate_base_yaml ----

class TestGenerateBaseYaml:
    def test_creates_base_file(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        result = split_mod.generate_base_yaml(
            '/etc/ssh/sshd_config', 'high', config, outdir, 75)

        assert os.path.exists(result)
        with open(result) as f:
            content = f.read()
        assert "Base configuration" in content

        # Parse past the comment line
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        assert doc['kind'] == 'MachineConfig'
        assert doc['spec']['config']['ignition']['version'] == '3.5.0'

    def test_severity_in_filename(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        result = split_mod.generate_base_yaml(
            '/etc/ssh/sshd_config', 'medium', config, outdir, 75)
        assert 'medium' in os.path.basename(result)

    def test_no_severity(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        result = split_mod.generate_base_yaml(
            '/etc/ssh/sshd_config', None, config, outdir, 75)
        basename = os.path.basename(result)
        assert 'high' not in basename
        assert 'medium' not in basename
        assert 'low' not in basename

    def test_include_dir_path_in_output(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        result = split_mod.generate_base_yaml(
            '/etc/ssh/sshd_config', None, config, outdir, 75)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        file_entry = doc['spec']['config']['storage']['files'][0]
        assert file_entry['path'] == (
            '/etc/ssh/sshd_config.d/00-include.conf')

    def test_base_content_encoded(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        split_mod.generate_base_yaml(
            '/etc/ssh/sshd_config', None, config, outdir, 75)

        outfile = os.path.join(outdir, "75-sshd_config-base.yaml")
        with open(outfile) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        source = doc['spec']['config']['storage']['files'][0][
            'contents']['source']
        decoded = urllib.parse.unquote(source.replace('data:,', ''))
        assert 'Include /etc/ssh/sshd_config.d/*.conf' in decoded

    def test_pam_base_file(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/pam.d/system-auth']
        result = split_mod.generate_base_yaml(
            '/etc/pam.d/system-auth', None, config, outdir, 75)
        assert os.path.exists(result)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        file_entry = doc['spec']['config']['storage']['files'][0]
        assert file_entry['path'] == (
            '/etc/pam.d/system-auth.d/00-include')


# ---- generate_modular_yaml ----

class TestGenerateModularYaml:
    def test_creates_modular_file(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'high/sshd-rem.yaml',
            'role': 'worker',
            'lines': ['PermitRootLogin no'],
            'basename': 'rhcos4-e8-worker-sshd-disable-root-login.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', 'high', info, config, outdir, 76)

        assert result is not None
        assert os.path.exists(result)

        with open(result) as f:
            content = f.read()
        assert "Modular configuration" in content
        assert "Source:" in content

    def test_returns_none_for_empty_settings(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['# only a comment'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', None, info, config, outdir, 76)
        assert result is None

    def test_role_in_metadata(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'master',
            'lines': ['PermitRootLogin no'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', None, info, config, outdir, 76)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        role = doc['metadata']['labels'][
            'machineconfiguration.openshift.io/role']
        assert role == 'master'

    def test_severity_in_filename(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['PermitRootLogin no'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', 'high', info, config, outdir, 76)
        assert 'high' in os.path.basename(result)

    def test_file_placed_in_d_directory(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['PermitRootLogin no'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', None, info, config, outdir, 76)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        file_path = doc['spec']['config']['storage']['files'][0]['path']
        assert file_path.startswith('/etc/ssh/sshd_config.d/')
        assert file_path.endswith('.conf')

    def test_content_encoded_correctly(self, outdir):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['PermitRootLogin no', 'Banner /etc/issue'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            '/etc/ssh/sshd_config', None, info, config, outdir, 76)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        source = doc['spec']['config']['storage']['files'][0][
            'contents']['source']
        decoded = urllib.parse.unquote(source.replace('data:,', ''))
        assert 'PermitRootLogin no' in decoded
        assert 'Banner /etc/issue' in decoded


# ---- write_combo_yaml (fallback for non-modular paths) ----

class TestWriteComboYaml:
    def test_creates_combo_file(self, outdir):
        sources = [
            {'lines': ['line1', 'line2']},
            {'lines': ['line2', 'line3']},
        ]
        result = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-test.conf', 'high', sources, outdir)
        assert os.path.exists(result)

    def test_deduplication(self, outdir):
        sources = [
            {'lines': ['aaa', 'bbb']},
            {'lines': ['bbb', 'ccc']},
        ]
        result = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-test.conf', None, sources, outdir)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        source = doc['spec']['config']['storage']['files'][0][
            'contents']['source']
        decoded = urllib.parse.unquote(source.replace('data:,', ''))
        decoded_lines = [
            ln for ln in decoded.strip().split('\n') if ln]
        assert len(decoded_lines) == 3
        assert sorted(decoded_lines) == ['aaa', 'bbb', 'ccc']

    def test_severity_in_name(self, outdir):
        sources = [{'lines': ['test']}]
        result = split_mod.write_combo_yaml(
            '/etc/test.conf', 'medium', sources, outdir)
        assert 'medium' in os.path.basename(result)

    def test_no_severity_in_name(self, outdir):
        sources = [{'lines': ['test']}]
        result = split_mod.write_combo_yaml(
            '/etc/test.conf', None, sources, outdir)
        basename = os.path.basename(result)
        assert basename.endswith('-combo.yaml')
        assert 'high' not in basename
        assert 'medium' not in basename

    def test_provenance_header(self, outdir):
        sources = [
            {'lines': ['line1']},
            {'lines': ['line2']},
        ]
        result = split_mod.write_combo_yaml(
            '/etc/test.conf', 'high', sources, outdir)
        with open(result) as f:
            first_line = f.readline()
        assert 'Combined from 2 remediations' in first_line

    def test_output_is_valid_machineconfig(self, outdir):
        sources = [{'lines': ['net.ipv4.ip_forward=1']}]
        result = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-net.conf', None, sources, outdir)

        with open(result) as f:
            content = f.read()
        lines = content.split('\n')
        yaml_content = '\n'.join(
            ln for ln in lines if not ln.startswith('#'))
        doc = yaml.safe_load(yaml_content)
        assert doc['kind'] == 'MachineConfig'
        assert doc['apiVersion'] == (
            'machineconfiguration.openshift.io/v1')
        assert doc['spec']['config']['ignition']['version'] == '3.5.0'


# ---- MODULAR_PATHS configuration ----

class TestModularPaths:
    def test_sshd_config_registered(self):
        assert '/etc/ssh/sshd_config' in split_mod.MODULAR_PATHS

    def test_pam_system_auth_registered(self):
        assert '/etc/pam.d/system-auth' in split_mod.MODULAR_PATHS

    def test_pam_password_auth_registered(self):
        assert '/etc/pam.d/password-auth' in split_mod.MODULAR_PATHS

    def test_sshd_include_dir(self):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        assert config['include_dir'] == '/etc/ssh/sshd_config.d'
        assert config['file_extension'] == '.conf'

    def test_pam_include_dir(self):
        config = split_mod.MODULAR_PATHS['/etc/pam.d/system-auth']
        assert config['include_dir'] == '/etc/pam.d/system-auth.d'
        assert config['file_extension'] == ''


# ---- Integration: end-to-end parse + generate ----

class TestEndToEnd:
    def test_modular_path_produces_base_and_modular(self, tmpdir, outdir):
        """SSHD config should produce base + modular output files."""
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no", "Banner /etc/issue"],
            name="rhcos4-e8-worker-sshd-disable-root-login")
        with open(os.path.join(tmpdir, "sshd-rem.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 1

        key = list(files_map.keys())[0]
        path, severity = key
        assert path == "/etc/ssh/sshd_config"
        config = split_mod.MODULAR_PATHS[path]

        base = split_mod.generate_base_yaml(
            path, severity, config, outdir, 75)
        assert os.path.exists(base)

        modular = split_mod.generate_modular_yaml(
            path, severity, files_map[key][0], config, outdir, 76)
        assert modular is not None
        assert os.path.exists(modular)

    def test_non_modular_path_produces_combo(self, tmpdir, outdir):
        """Paths not in MODULAR_PATHS should produce combo output."""
        mc = make_mc_yaml(
            "/etc/sysctl.d/99-compliance.conf",
            ["net.ipv4.ip_forward=1"])
        with open(os.path.join(tmpdir, "sysctl.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        path, severity = key

        assert path not in split_mod.MODULAR_PATHS
        combo = split_mod.write_combo_yaml(
            path, severity, files_map[key], outdir)
        assert os.path.exists(combo)

    def test_multiple_remediations_same_modular_path(
            self, tmpdir, outdir):
        """Multiple SSHD remediations should each get a modular file."""
        mc1 = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"],
            name="mc1")
        mc2 = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PasswordAuthentication no"],
            name="mc2")
        with open(os.path.join(tmpdir, "mc1.yaml"), 'w') as f:
            yaml.dump(mc1, f)
        with open(os.path.join(tmpdir, "mc2.yaml"), 'w') as f:
            yaml.dump(mc2, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        key = list(files_map.keys())[0]
        path = key[0]
        config = split_mod.MODULAR_PATHS[path]

        created = []
        for idx, source in enumerate(files_map[key], start=76):
            result = split_mod.generate_modular_yaml(
                path, key[1], source, config, outdir, idx)
            if result:
                created.append(result)
        assert len(created) == 2

    def test_mixed_modular_and_non_modular(self, tmpdir, outdir):
        """Mix of SSHD (modular) and sysctl (non-modular) files."""
        mc_sshd = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no"])
        mc_sysctl = make_mc_yaml(
            "/etc/sysctl.d/99-net.conf",
            ["net.ipv4.ip_forward=1"])
        with open(os.path.join(tmpdir, "sshd.yaml"), 'w') as f:
            yaml.dump(mc_sshd, f)
        with open(os.path.join(tmpdir, "sysctl.yaml"), 'w') as f:
            yaml.dump(mc_sysctl, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 2

        modular_count = 0
        non_modular_count = 0
        for (path, _), _ in files_map.items():
            if path in split_mod.MODULAR_PATHS:
                modular_count += 1
            else:
                non_modular_count += 1
        assert modular_count == 1
        assert non_modular_count == 1
