#!/usr/bin/env python3
"""Tests for modular/split-machineconfigs-modular.py"""
from __future__ import annotations

import os
import sys
import tempfile
import shutil
import urllib.parse
from typing import Any

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

ROLE_LABEL = 'machineconfiguration.openshift.io/role'

# Synthetic config for a path that DOES need a base MC (sshd does not).
FAKE_MODULAR_PATH = '/etc/fake/daemon.conf'
NEEDS_BASE_CONFIG = {
    'include_dir': '/etc/fake/daemon.conf.d',
    'base_file': '00-include.conf',
    'base_content': 'Include /etc/fake/daemon.conf.d/*.conf',
    'file_extension': '.conf',
    'needs_base': True,
}

# NEEDS_BASE_CONFIG minus the base-file keys: a modular path that
# neither needs a base MC nor carries a dropin prefix
NO_PREFIX_CONFIG = {
    'include_dir': NEEDS_BASE_CONFIG['include_dir'],
    'file_extension': NEEDS_BASE_CONFIG['file_extension'],
}

# RHCOS stock files in /etc/ssh/sshd_config.d; generated drop-ins must
# sort before these (sshd is first-match-wins)
STOCK_SSHD_DROPINS = ('40-rhcos-defaults.conf', '50-redhat.conf')


def load_mc(path: str) -> dict[str, Any]:
    """Load a generated MachineConfig YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def decode_content(doc: dict[str, Any]) -> str:
    """Decode the data: source of the first storage file in an MC."""
    source = doc['spec']['config']['storage']['files'][0]['contents'][
        'source']
    return urllib.parse.unquote(source.replace('data:,', ''))


def write_remediation(
    tmpdir: str,
    name: str,
    path: str,
    lines: list[str],
    role: str = 'worker',
    subdir: str | None = None,
) -> None:
    """Write a remediation MachineConfig YAML into tmpdir."""
    d = tmpdir if subdir is None else os.path.join(tmpdir, subdir)
    os.makedirs(d, exist_ok=True)
    mc = make_mc_yaml(path, lines, name=name, role=role)
    with open(os.path.join(d, f"{name}.yaml"), 'w') as f:
        yaml.dump(mc, f)


def make_mc_yaml(
    path: str,
    lines: list[str],
    name: str = "test-mc",
    role: str = "worker",
) -> dict[str, Any]:
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


def make_mc_yaml_systemd(
    units: list[dict[str, Any]],
    name: str = "test-mc",
    role: str = "worker",
) -> dict[str, Any]:
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


def make_mc_yaml_kernelargs(
    kargs: list[str],
    name: str = "test-mc",
    role: str = "worker",
) -> dict[str, Any]:
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


# ---- stable numbering ----

class TestStableRemediationCounters:
    @staticmethod
    def source(source_file: str) -> dict[str, Any]:
        return {
            'source_file': source_file,
            'role': 'worker',
            'lines': [f'{source_file}=value'],
            'basename': os.path.basename(source_file),
        }

    def test_order_is_independent_of_input_order(self):
        sources = [
            self.source('medium/second.yaml'),
            self.source('high/first.yaml'),
        ]

        first = split_mod.stable_remediation_counters(
            '/etc/ssh/sshd_config', 'high', sources)
        second = split_mod.stable_remediation_counters(
            '/etc/ssh/sshd_config', 'high', list(reversed(sources)))

        first_numbers = {source['source_file']: number
                         for number, source in first}
        second_numbers = {source['source_file']: number
                          for number, source in second}
        assert first_numbers == second_numbers

    def test_unrelated_source_does_not_renumber_existing_sources(self):
        existing = [
            self.source('high/first.yaml'),
            self.source('high/second.yaml'),
        ]
        with_unrelated = existing + [self.source('high/new-unrelated.yaml')]

        before = split_mod.stable_remediation_counters(
            '/etc/ssh/sshd_config', 'high', existing)
        after = split_mod.stable_remediation_counters(
            '/etc/ssh/sshd_config', 'high', with_unrelated)

        before_numbers = {source['source_file']: number
                          for number, source in before}
        after_numbers = {source['source_file']: number
                         for number, source in after}
        assert {key: after_numbers[key] for key in before_numbers} == before_numbers

    def test_base_counter_is_reserved(self):
        planned = split_mod.stable_remediation_counters(
            '/etc/ssh/sshd_config', 'high', [self.source('high/test.yaml')])

        assert planned[0][0] != split_mod.BASE_COUNTER
        assert planned[0][0] >= split_mod.FIRST_REMEDIATION_COUNTER

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
        result = split_mod.generate_base_yaml(
            FAKE_MODULAR_PATH, 'worker', NEEDS_BASE_CONFIG, outdir, 75)

        assert os.path.exists(result)
        with open(result) as f:
            content = f.read()
        assert "Base configuration" in content

        doc = load_mc(result)
        assert doc['kind'] == 'MachineConfig'
        assert doc['spec']['config']['ignition']['version'] == '3.5.0'

    def test_role_in_filename(self, outdir):
        result = split_mod.generate_base_yaml(
            FAKE_MODULAR_PATH, 'master', NEEDS_BASE_CONFIG, outdir, 75)
        assert 'master' in os.path.basename(result)

    def test_role_in_metadata(self, outdir):
        result = split_mod.generate_base_yaml(
            FAKE_MODULAR_PATH, 'master', NEEDS_BASE_CONFIG, outdir, 75)
        doc = load_mc(result)
        assert doc['metadata']['labels'][ROLE_LABEL] == 'master'

    def test_include_dir_path_in_output(self, outdir):
        result = split_mod.generate_base_yaml(
            FAKE_MODULAR_PATH, 'worker', NEEDS_BASE_CONFIG, outdir, 75)

        doc = load_mc(result)
        file_entry = doc['spec']['config']['storage']['files'][0]
        assert file_entry['path'] == (
            '/etc/fake/daemon.conf.d/00-include.conf')

    def test_base_content_encoded(self, outdir):
        result = split_mod.generate_base_yaml(
            FAKE_MODULAR_PATH, 'worker', NEEDS_BASE_CONFIG, outdir, 75)

        doc = load_mc(result)
        assert 'Include /etc/fake/daemon.conf.d/*.conf' in decode_content(doc)


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

        doc = load_mc(result)
        file_path = doc['spec']['config']['storage']['files'][0]['path']
        # dropin_prefix + zero-padded counter on the node; the MC
        # object name keeps the 76+ counter
        assert file_path == '/etc/ssh/sshd_config.d/10-0076-test.conf'
        assert doc['metadata']['name'].startswith('76-')

    def test_dropin_sorts_before_stock_files(self, outdir):
        """sshd is first-match-wins and reads sshd_config.d in lexical
        order, so every generated drop-in must sort before RHCOS's
        stock drop-ins."""
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['PermitRootLogin no'],
            'basename': 'test.yaml',
        }
        basenames = []
        for counter in (split_mod.FIRST_REMEDIATION_COUNTER, 777,
                        split_mod.MAX_REMEDIATION_COUNTER):
            result = split_mod.generate_modular_yaml(
                '/etc/ssh/sshd_config', None, info, config, outdir, counter)
            doc = load_mc(result)
            entry = doc['spec']['config']['storage']['files'][0]
            basename = os.path.basename(entry['path'])
            for stock in STOCK_SSHD_DROPINS:
                assert basename < stock
            basenames.append(basename)
        # zero padding keeps lexical order == counter order among the
        # generated drop-ins (remediation precedence)
        assert basenames == sorted(basenames)

    def test_no_dropin_prefix_uses_counter_name(self, outdir):
        """Paths without a dropin_prefix keep the legacy on-node name:
        the counter alone as the prefix."""
        info = {
            'source_file': 'test.yaml',
            'role': 'worker',
            'lines': ['SettingOne yes'],
            'basename': 'test.yaml',
        }
        result = split_mod.generate_modular_yaml(
            FAKE_MODULAR_PATH, None, info, NO_PREFIX_CONFIG, outdir, 76)

        doc = load_mc(result)
        entry = doc['spec']['config']['storage']['files'][0]
        assert entry['path'] == '/etc/fake/daemon.conf.d/76-test.conf'

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
    @staticmethod
    def source(lines: list[str], role: str = 'worker',
               name: str | None = None) -> dict[str, Any]:
        filename = name or f'{role}-rem.yaml'
        return {
            'source_file': filename,
            'role': role,
            'lines': lines,
            'basename': filename,
        }

    def test_creates_combo_file(self, outdir):
        sources = [
            self.source(['line1', 'line2']),
            self.source(['line2', 'line3']),
        ]
        results = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-test.conf', 'high', sources, outdir)
        assert len(results) == 1
        assert os.path.exists(results[0])

    def test_deduplication(self, outdir):
        first = self.source(['zzz', 'aaa'], name='a-first')
        second = self.source(['aaa', 'mmm'], name='b-second')
        results = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-test.conf', None, [second, first], outdir)

        decoded_lines = [
            ln for ln in decode_content(load_mc(results[0])).split('\n')
            if ln]
        # sources merge in stable source order with the first occurrence
        # of a line winning -- not alphabetically sorted
        assert decoded_lines == ['zzz', 'aaa', 'mmm']

    def test_one_combo_per_role(self, outdir):
        sources = [
            self.source(['PermitRootLogin no'], role='master'),
            self.source(['PermitRootLogin no'], role='worker'),
        ]
        results = split_mod.write_combo_yaml(
            '/etc/pam.d/system-auth', None, sources, outdir)
        assert len(results) == 2

        docs = [load_mc(r) for r in results]
        roles = sorted(doc['metadata']['labels'][ROLE_LABEL] for doc in docs)
        assert roles == ['master', 'worker']
        for doc in docs:
            assert decode_content(doc).strip() == 'PermitRootLogin no'

    def test_combo_preserves_line_order(self, outdir):
        """PAM stacks are order-sensitive: pam_faillock authfail must run
        after preauth, which alphabetical sorting would break."""
        ordered = [
            'auth        required      pam_faillock.so preauth',
            'auth        sufficient    pam_unix.so try_first_pass nullok',
            'auth        required      pam_faillock.so authfail',
        ]
        results = split_mod.write_combo_yaml(
            '/etc/pam.d/system-auth', None, [self.source(ordered)], outdir)

        decoded_lines = [
            ln for ln in decode_content(load_mc(results[0])).split('\n')
            if ln]
        assert decoded_lines == ordered

    def test_severity_in_name(self, outdir):
        sources = [self.source(['test'])]
        results = split_mod.write_combo_yaml(
            '/etc/test.conf', 'medium', sources, outdir)
        assert 'medium' in os.path.basename(results[0])

    def test_no_severity_in_name(self, outdir):
        sources = [self.source(['test'])]
        results = split_mod.write_combo_yaml(
            '/etc/test.conf', None, sources, outdir)
        basename = os.path.basename(results[0])
        assert basename.endswith('-combo-worker.yaml')
        assert 'high' not in basename
        assert 'medium' not in basename

    def test_provenance_header(self, outdir):
        sources = [
            self.source(['line1']),
            self.source(['line2']),
        ]
        results = split_mod.write_combo_yaml(
            '/etc/test.conf', 'high', sources, outdir)
        with open(results[0]) as f:
            first_line = f.readline()
        assert 'Combined from 2 remediations' in first_line

    def test_output_is_valid_machineconfig(self, outdir):
        sources = [self.source(['net.ipv4.ip_forward=1'])]
        results = split_mod.write_combo_yaml(
            '/etc/sysctl.d/99-net.conf', None, sources, outdir)

        doc = load_mc(results[0])
        assert doc['kind'] == 'MachineConfig'
        assert doc['apiVersion'] == (
            'machineconfiguration.openshift.io/v1')
        assert doc['spec']['config']['ignition']['version'] == '3.5.0'


# ---- MODULAR_PATHS configuration ----

class TestModularPaths:
    def test_sshd_config_registered(self):
        assert '/etc/ssh/sshd_config' in split_mod.MODULAR_PATHS

    def test_sshd_needs_no_base(self):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        assert config['needs_base'] is False

    def test_pam_paths_not_modular(self):
        assert '/etc/pam.d/system-auth' not in split_mod.MODULAR_PATHS
        assert '/etc/pam.d/password-auth' not in split_mod.MODULAR_PATHS

    def test_sshd_include_dir(self):
        config = split_mod.MODULAR_PATHS['/etc/ssh/sshd_config']
        assert config['include_dir'] == '/etc/ssh/sshd_config.d'
        assert config['file_extension'] == '.conf'


# ---- generate_outputs (orchestration) ----

class TestGenerateOutputs:
    def test_sshd_generation_has_no_self_referential_include(
            self, tmpdir, outdir):
        """No generated file may sit inside a directory its own Include
        glob matches."""
        write_remediation(
            tmpdir, 'sshd-root-login', '/etc/ssh/sshd_config',
            ['PermitRootLogin no'], role='worker')
        write_remediation(
            tmpdir, 'sshd-master-banner', '/etc/ssh/sshd_config',
            ['Banner /etc/issue'], role='master')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)
        assert len(outputs) == 2

        for outpath in outputs:
            doc = load_mc(outpath)
            content = decode_content(doc)
            for entry in doc['spec']['config']['storage']['files']:
                assert not os.path.basename(
                    entry['path']).startswith('00-include')
                for line in content.splitlines():
                    assert not line.lower().startswith('include ')
                    assert not line.lower().startswith('@include ')

    def test_sshd_dropins_sort_before_stock_files(self, tmpdir, outdir):
        """End to end: every sshd_config.d path must sort before RHCOS's
        stock drop-ins (sshd first-match-wins)."""
        write_remediation(
            tmpdir, 'sshd-root-login', '/etc/ssh/sshd_config',
            ['PermitRootLogin no'], role='worker')
        write_remediation(
            tmpdir, 'sshd-banner', '/etc/ssh/sshd_config',
            ['Banner /etc/issue'], role='master')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)

        for outpath in outputs:
            doc = load_mc(outpath)
            for entry in doc['spec']['config']['storage']['files']:
                if entry['path'].startswith('/etc/ssh/sshd_config.d/'):
                    basename = os.path.basename(entry['path'])
                    for stock in STOCK_SSHD_DROPINS:
                        assert basename < stock

    def test_pam_falls_through_to_combo(self, tmpdir, outdir):
        """PAM paths are not .d-capable and must produce full-file combo
        MCs on the role the remediation targets."""
        write_remediation(
            tmpdir, 'pam-no-empty-passwords', '/etc/pam.d/system-auth',
            ['auth required pam_unix.so nullok'], role='master')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)

        assert len(outputs) == 1
        doc = load_mc(outputs[0])
        assert '-combo-' in doc['metadata']['name']
        entry = doc['spec']['config']['storage']['files'][0]
        assert entry['path'] == '/etc/pam.d/system-auth'
        assert doc['metadata']['labels'][ROLE_LABEL] == 'master'

    def test_base_roles_match_dropin_roles(self, tmpdir, outdir,
                                           monkeypatch):
        """A path that needs a base MC gets one per role, matching the
        roles its drop-ins target."""
        monkeypatch.setattr(
            split_mod, 'MODULAR_PATHS',
            {FAKE_MODULAR_PATH: dict(NEEDS_BASE_CONFIG)})
        write_remediation(
            tmpdir, 'fake-worker', FAKE_MODULAR_PATH, ['SettingOne yes'])
        write_remediation(
            tmpdir, 'fake-master', FAKE_MODULAR_PATH, ['SettingOne yes'],
            role='master')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)

        docs = [load_mc(o) for o in outputs]
        base_roles = sorted(
            doc['metadata']['labels'][ROLE_LABEL]
            for doc in docs if '-base-' in doc['metadata']['name'])
        dropin_roles = sorted(
            doc['metadata']['labels'][ROLE_LABEL]
            for doc in docs if '-base-' not in doc['metadata']['name'])
        assert base_roles == ['master', 'worker']
        assert dropin_roles == ['master', 'worker']

    def test_base_emitted_once_across_severities(self, tmpdir, outdir,
                                                 monkeypatch):
        """The base MC is per (path, role), not per severity group."""
        monkeypatch.setattr(
            split_mod, 'MODULAR_PATHS',
            {FAKE_MODULAR_PATH: dict(NEEDS_BASE_CONFIG)})
        write_remediation(
            tmpdir, 'fake-high', FAKE_MODULAR_PATH, ['SettingOne yes'],
            subdir='high')
        write_remediation(
            tmpdir, 'fake-medium', FAKE_MODULAR_PATH, ['SettingTwo no'],
            subdir='medium')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)

        docs = [load_mc(o) for o in outputs]
        bases = [doc for doc in docs if '-base-' in doc['metadata']['name']]
        assert len(bases) == 1

    def test_base_emitted_once_per_role_across_severities(
            self, tmpdir, outdir, monkeypatch):
        """Two severities x two roles yields exactly one base MC per
        role, not one per severity."""
        monkeypatch.setattr(
            split_mod, 'MODULAR_PATHS',
            {FAKE_MODULAR_PATH: dict(NEEDS_BASE_CONFIG)})
        write_remediation(
            tmpdir, 'high-worker', FAKE_MODULAR_PATH, ['SettingOne yes'],
            subdir='high')
        write_remediation(
            tmpdir, 'high-master', FAKE_MODULAR_PATH, ['SettingOne yes'],
            role='master', subdir='high')
        write_remediation(
            tmpdir, 'medium-worker', FAKE_MODULAR_PATH, ['SettingTwo no'],
            subdir='medium')

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        outputs = split_mod.generate_outputs(files_map, outdir)

        docs = [load_mc(o) for o in outputs]
        base_roles = sorted(
            doc['metadata']['labels'][ROLE_LABEL]
            for doc in docs if '-base-' in doc['metadata']['name'])
        assert base_roles == ['master', 'worker']


# ---- Integration: end-to-end parse + generate ----

class TestEndToEnd:
    def test_modular_path_produces_modular_only(self, tmpdir, outdir):
        """SSHD config produces modular drop-ins and no base include MC."""
        mc = make_mc_yaml(
            "/etc/ssh/sshd_config",
            ["PermitRootLogin no", "Banner /etc/issue"],
            name="rhcos4-e8-worker-sshd-disable-root-login")
        with open(os.path.join(tmpdir, "sshd-rem.yaml"), 'w') as f:
            yaml.dump(mc, f)

        files_map, _ = split_mod.parse_machineconfig_files(tmpdir)
        assert len(files_map) == 1

        outputs = split_mod.generate_outputs(files_map, outdir)
        assert len(outputs) == 1

        doc = load_mc(outputs[0])
        assert '-base-' not in doc['metadata']['name']
        entry = doc['spec']['config']['storage']['files'][0]
        assert entry['path'].startswith('/etc/ssh/sshd_config.d/')

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
        combos = split_mod.write_combo_yaml(
            path, severity, files_map[key], outdir)
        assert len(combos) == 1
        assert os.path.exists(combos[0])

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
