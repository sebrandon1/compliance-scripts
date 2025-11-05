#!/usr/bin/env python3
"""
Split MachineConfig remediations into modular .d directory files.
Creates base files that enable include directories and individual
files for each setting.
"""
import os
import urllib.parse
import yaml
import argparse
from collections import defaultdict


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


def safe_shortname(path):
    """Convert a file path to a safe shortname for filenames."""
    import re
    basename = os.path.basename(path)

    # For files starting with numbering, extract the meaningful part
    match = re.match(r'(\d+-)?(.+?)(?:\.[^.]+)?$', basename)
    if match:
        prefix = match.group(1) or ''
        name = match.group(2)
        return f"{prefix}{name}"

    # Clean up the basename
    name = re.sub(r'\.[^.]+$', '', basename)  # Remove extension
    name = re.sub(r'[^a-zA-Z0-9\-_]', '-', name)  # Replace special chars
    name = re.sub(r'-+', '-', name)  # Collapse multiple hyphens
    return name.strip('-')


def parse_machineconfig_files(src_dir):
    """Parse all MachineConfig YAMLs and group by (file path, severity)."""
    files_map = defaultdict(
        list)  # (path, severity) -> list of (source_file, role, decoded_lines)

    severity_names = {"high", "medium", "low"}

    for root, dirs, files in os.walk(src_dir):
        # Determine severity from the relative root path segments
        rel_root = os.path.relpath(root, src_dir)
        parts = [
            p.lower() for p in rel_root.split(
                os.sep) if p not in (
                ".", "")]
        severity = None
        for p in parts:
            if p in severity_names:
                severity = p
                break

        for fname in files:
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(root, fname)
            if not os.path.isfile(fpath):
                continue

            with open(fpath) as f:
                docs = list(yaml.safe_load_all(f))

            for doc in docs:
                if not doc or doc.get('kind') != 'MachineConfig':
                    continue

                # Extract role from labels or metadata name
                role = doc.get('metadata', {}).get('labels', {}).get(
                    'machineconfiguration.openshift.io/role', 'worker'
                )

                files_entries = doc.get(
                    'spec',
                    {}).get(
                    'config',
                    {}).get(
                    'storage',
                    {}).get(
                    'files',
                    [])
                for file_entry in files_entries:
                    path = file_entry.get('path')
                    source = file_entry.get('contents', {}).get('source')
                    if path and source and source.startswith('data:,'):
                        decoded = urllib.parse.unquote(source[6:])
                        lines = [
                            line for line in decoded.splitlines()
                            if line.strip()
                        ]
                        files_map[(path, severity)].append({
                            'source_file': os.path.relpath(fpath, src_dir),
                            'role': role,
                            'lines': lines,
                            'basename': os.path.basename(fpath)
                        })

    return files_map


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
                    'version': '3.1.0'
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
                    'version': '3.1.0'
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
                    'version': '3.1.0'
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

    # Parse and validate severity filter
    severity_filter = None
    if args.severity:
        raw = args.severity.strip().lower().replace(' ', '')
        requested = [s for s in raw.split(',') if s]
        valid = {"high", "medium", "low"}
        invalid = [s for s in requested if s not in valid]
        if invalid:
            raise SystemExit(
                f"Invalid severity: {
                    ','.join(invalid)}. Allowed: high, medium, low")
        severity_filter = set(requested)

    os.makedirs(out_dir, exist_ok=True)

    # Parse MachineConfig files
    files_map = parse_machineconfig_files(src_dir)

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


if __name__ == "__main__":
    main()
