#!/usr/bin/env python3
"""
Split MachineConfig remediations into modular .d directory files.
Creates base files that enable include directories and individual
files for each setting.
"""
import os
import sys
import urllib.parse
import yaml
import argparse

# Add project root to path for shared module imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from lib.compliance_utils import (  # noqa: E402
    safe_shortname, parse_machineconfig_files, parse_severity_filter,
)


IGNITION_VERSION = '3.5.0'

# Configuration for paths that support .d directory includes
MODULAR_PATHS = {
    '/etc/ssh/sshd_config': {
        'include_dir': '/etc/ssh/sshd_config.d',
        'base_file': '00-include.conf',
        'base_content': 'Include /etc/ssh/sshd_config.d/*.conf',
        'file_extension': '.conf',
    },
    '/etc/pam.d/system-auth': {
        'include_dir': '/etc/pam.d/system-auth.d',
        'base_file': '00-include',
        'base_content': '@include system-auth.d/*',
        'file_extension': '',
    },
    '/etc/pam.d/password-auth': {
        'include_dir': '/etc/pam.d/password-auth.d',
        'base_file': '00-include',
        'base_content': '@include password-auth.d/*',
        'file_extension': '',
    },
}


def extract_meaningful_settings(lines):
    """Extract meaningful (non-comment, non-empty) settings from lines."""
    settings = []
    for line in lines:
        stripped = line.strip()
        # Skip empty lines and full-line comments
        if not stripped or stripped.startswith('#'):
            continue
        # Skip Include directives as they should only be in base files
        if stripped.lower().startswith('include '):
            continue
        # Skip @include directives for PAM files
        if stripped.lower().startswith('@include '):
            continue
        settings.append(line)
    return settings


def generate_base_yaml(path, severity, config, out_dir, counter):
    """Generate a base MachineConfig that enables the .d include directory."""
    shortname = safe_shortname(path)
    if severity:
        filename = f"{counter:02d}-{shortname}-base-{severity}.yaml"
        name = f"{counter:02d}-{shortname}-base-{severity}"
    else:
        filename = f"{counter:02d}-{shortname}-base.yaml"
        name = f"{counter:02d}-{shortname}-base"

    include_path = os.path.join(config['include_dir'], config['base_file'])
    content = config['base_content']

    encoded_content = urllib.parse.quote(content + '\n', safe='')
    yaml_doc = {
        'apiVersion': 'machineconfiguration.openshift.io/v1',
        'kind': 'MachineConfig',
        'metadata': {
            'name': name,
            'labels': {
                'machineconfiguration.openshift.io/role': 'worker'
            }
        },
        'spec': {
            'config': {
                'ignition': {
                    'version': IGNITION_VERSION
                },
                'storage': {
                    'files': [
                        {
                            'contents': {
                                'source': f"data:,{encoded_content}"
                            },
                            'mode': 0o644,
                            'overwrite': True,
                            'path': include_path
                        }
                    ]
                }
            }
        }
    }

    outpath = os.path.join(out_dir, filename)
    with open(outpath, 'w') as f:
        f.write(
            f"# Base configuration that enables {
                config['include_dir']} for modular configuration management\n")
        yaml.dump(yaml_doc, f, default_flow_style=False, sort_keys=False)

    print(f"Created base file: {outpath}")
    return outpath


def generate_modular_yaml(
        path,
        severity,
        remediation_info,
        config,
        out_dir,
        counter):
    """Generate a modular MachineConfig for a specific remediation."""
    source_file = remediation_info['source_file']
    role = remediation_info['role']
    lines = remediation_info['lines']
    basename = remediation_info['basename']

    # Extract meaningful settings
    settings = extract_meaningful_settings(lines)
    if not settings:
        return None

    # Create a descriptive name from the source file
    # Remove common prefixes and suffixes
    desc = basename.replace(
        '.yaml',
        '').replace(
        'rhcos4-e8-',
        '').replace(
            'master-',
            '').replace(
                'worker-',
        '')
    desc = desc.replace('sshd-', '').replace('pam-', '')

    shortname = safe_shortname(path)
    if severity:
        filename = f"{counter:02d}-{shortname}-{desc}-{role}-{severity}.yaml"
        name = f"{counter:02d}-{shortname}-{desc}-{role}-{severity}"
    else:
        filename = f"{counter:02d}-{shortname}-{desc}-{role}.yaml"
        name = f"{counter:02d}-{shortname}-{desc}-{role}"

    # Determine the actual config file name in the .d directory
    config_filename = f"{counter:02d}-{desc}{config['file_extension']}"
    config_path = os.path.join(config['include_dir'], config_filename)

    content = '\n'.join(settings) + '\n'
    encoded_content = urllib.parse.quote(content, safe='')

    yaml_doc = {
        'apiVersion': 'machineconfiguration.openshift.io/v1',
        'kind': 'MachineConfig',
        'metadata': {
            'name': name,
            'labels': {
                'machineconfiguration.openshift.io/role': role
            }
        },
        'spec': {
            'config': {
                'ignition': {
                    'version': IGNITION_VERSION
                },
                'storage': {
                    'files': [
                        {
                            'contents': {
                                'source': f"data:,{encoded_content}"
                            },
                            'mode': 0o644,
                            'overwrite': True,
                            'path': config_path
                        }
                    ]
                }
            }
        }
    }

    outpath = os.path.join(out_dir, filename)
    with open(outpath, 'w') as f:
        f.write(f"# Modular configuration for {desc}\n")
        f.write(f"# Source: {source_file}\n")
        yaml.dump(yaml_doc, f, default_flow_style=False, sort_keys=False)

    print(f"Created modular file: {outpath}")
    return outpath


def write_combo_yaml(path, severity, sources, out_dir):
    """Write a combined MachineConfig YAML (fallback for non-modular paths)."""
    all_lines = set()
    for source in sources:
        all_lines.update(source['lines'])
    deduped_lines = sorted(all_lines)

    shortname = safe_shortname(path)
    if severity:
        filename = f"{shortname}-{severity}-combo.yaml"
        name = f"75-{shortname}-{severity}-combo"
    else:
        filename = f"{shortname}-combo.yaml"
        name = f"75-{shortname}-combo"

    content = '\n'.join(deduped_lines) + '\n'
    encoded_content = urllib.parse.quote(content, safe='')

    yaml_doc = {
        'apiVersion': 'machineconfiguration.openshift.io/v1',
        'kind': 'MachineConfig',
        'metadata': {
            'name': name,
            'labels': {
                'machineconfiguration.openshift.io/role': 'worker'
            }
        },
        'spec': {
            'config': {
                'ignition': {
                    'version': IGNITION_VERSION
                },
                'storage': {
                    'files': [
                        {
                            'contents': {
                                'source': f"data:,{encoded_content}"
                            },
                            'mode': 0o600,
                            'overwrite': True,
                            'path': path
                        }
                    ]
                }
            }
        }
    }

    outpath = os.path.join(out_dir, filename)
    with open(outpath, 'w') as f:
        f.write(f"# Combined from {len(sources)} remediations for {path}\n")
        if severity:
            f.write(f"# Severity: {severity}\n")
        yaml.dump(yaml_doc, f, default_flow_style=False, sort_keys=False)

    print(f"Created combo file: {outpath}")
    return outpath


def main():
    parser = argparse.ArgumentParser(
        description="Split MachineConfig remediations into modular "
                    ".d directory files.")
    parser.add_argument(
        '--src-dir', default='complianceremediations',
        help='Source directory containing MachineConfig YAMLs'
    )
    parser.add_argument(
        '--out-dir', default='complianceremediations/modular',
        help='Directory to write modular YAMLs'
    )
    parser.add_argument(
        '-s', '--severity', default=None,
        help='Comma-separated severities to include: high,medium,low'
    )
    args = parser.parse_args()

    src_dir = args.src_dir
    out_dir = args.out_dir

    severity_filter = parse_severity_filter(args.severity)

    os.makedirs(out_dir, exist_ok=True)

    # Parse MachineConfig files
    files_map, skipped = parse_machineconfig_files(src_dir)

    # Filter by severity if specified
    if severity_filter is not None:
        files_map = {
            (path, sev): sources
            for (path, sev), sources in files_map.items()
            if sev in severity_filter
        }

    created_files = []

    # Process each (path, severity) combination
    for (path, severity), sources in sorted(files_map.items()):
        if len(sources) < 1:
            continue

        # Check if this path supports modular configuration
        if path in MODULAR_PATHS:
            config = MODULAR_PATHS[path]
            print(
                f"\nProcessing modular path: {path} (severity: {
                    severity or 'all'})")

            # Generate base file (only once per path)
            base_file = generate_base_yaml(path, severity, config, out_dir, 75)
            created_files.append(base_file)

            # Generate individual modular files
            for idx, source in enumerate(sources, start=76):
                modular_file = generate_modular_yaml(
                    path, severity, source, config, out_dir, idx
                )
                if modular_file:
                    created_files.append(modular_file)
        else:
            # Fallback to combo file for non-modular paths
            sev = severity or 'all'
            print(
                f"\nProcessing non-modular path: {path} (severity: {sev})")
            combo_file = write_combo_yaml(path, severity, sources, out_dir)
            created_files.append(combo_file)

    print(f"\n{'=' * 60}")
    print(f"Generated {len(created_files)} files in {out_dir}/")
    print(f"{'=' * 60}")

    if skipped:
        print(f"\nWARNING: {len(skipped)} file(s) skipped due to YAML parse errors:",
              file=sys.stderr)
        for fpath, err in skipped:
            print(f"  - {fpath}: {err}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
