#!/usr/bin/env python3
"""
Split MachineConfig remediations into modular .d directory files,
one drop-in MachineConfig per remediation.

Paths whose daemon does not natively read a .d directory can opt into a
generated base MC (``needs_base``). sshd needs none because RHCOS's stock
sshd_config already includes sshd_config.d/*.conf. PAM is not .d-capable
at all, so PAM remediations fall back to full-file combo MCs.

Generated output is staged and validated (see validate_outputs) before
it replaces prior output, so a failed run cannot leave a partial set.
"""
from __future__ import annotations

import os
import sys
import shutil
import tempfile
import urllib.parse
import yaml
import argparse
import hashlib
from typing import Any

# Add project root to path for shared module imports
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from lib.compliance_utils import (  # noqa: E402
    safe_shortname, parse_machineconfig_files, parse_severity_filter,
    decode_data_source,
)


IGNITION_VERSION = '3.5.0'
ROLE_LABEL_KEY = 'machineconfiguration.openshift.io/role'
BASE_COUNTER = 75
FIRST_REMEDIATION_COUNTER = BASE_COUNTER + 1
MAX_REMEDIATION_COUNTER = 9999
SEVERITY_ORDER = {'high': 0, 'medium': 1, 'low': 2, None: 3}

# Configuration for paths that support .d directory includes.
#
# PAM is deliberately absent: Linux-PAM's @include takes a single file,
# not a glob, and RHCOS /etc/pam.d/system-auth is authselect-managed with
# nothing referencing a system-auth.d/ directory. A drop-in written there
# would be a dead file, so PAM remediations fall through to
# write_combo_yaml(), which writes the full merged file the same way
# Compliance Operator remediations do.
MODULAR_PATHS: dict[str, dict[str, Any]] = {
    # RHCOS's stock /etc/ssh/sshd_config already contains
    # 'Include /etc/ssh/sshd_config.d/*.conf', so no base MC is needed.
    # Generating one would place an Include inside the directory its own
    # glob matches. Verify on the target node with:
    #   grep Include /etc/ssh/sshd_config
    # sshd keeps the FIRST value it reads for each keyword (first match
    # wins) and reads sshd_config.d/*.conf in lexical order. Stock RHCOS
    # ships 40-rhcos-defaults.conf and 50-redhat.conf (which sets, e.g.,
    # X11Forwarding yes), so generated drop-ins must sort before the
    # stock files or any keyword they share is silently ignored.
    # dropin_prefix places every generated drop-in ahead of them, while
    # the zero-padded counter preserves remediation precedence among
    # the generated files themselves.
    '/etc/ssh/sshd_config': {
        'include_dir': '/etc/ssh/sshd_config.d',
        'file_extension': '.conf',
        'needs_base': False,
        'dropin_prefix': '10',
        # Keywords that legitimately repeat — each line adds a value
        # instead of first-match-wins — so they are exempt from the
        # duplicate-setting conflict check in validate_outputs.
        'repeatable_keywords': (
            'AcceptEnv', 'AllowGroups', 'AllowUsers', 'DenyGroups',
            'DenyUsers', 'HostCertificate', 'HostKey', 'ListenAddress',
            'PermitListen', 'PermitOpen', 'Port',
        ),
    },
}


def source_sort_key(remediation_info: dict[str, Any]) -> tuple[str, ...]:
    """Return a stable ordering key for a remediation source."""
    return (
        str(remediation_info.get('source_file', '')).casefold(),
        str(remediation_info.get('role', '')).casefold(),
        str(remediation_info.get('basename', '')).casefold(),
        '\n'.join(remediation_info.get('lines', [])),
    )


def group_sort_key(
        group: tuple[tuple[str, str | None], list[dict[str, Any]]]
) -> tuple[int, int, str]:
    """Sort paths, then severities, independently of filesystem traversal."""
    (path, severity), _sources = group
    path_order = list(MODULAR_PATHS).index(path) if path in MODULAR_PATHS else len(MODULAR_PATHS)
    severity_order = SEVERITY_ORDER.get(severity, len(SEVERITY_ORDER))
    return path_order, severity_order, path


def stable_remediation_counters(
        path: str,
        severity: str | None,
        sources: list[dict[str, Any]],
) -> list[tuple[int, dict[str, Any]]]:
    """Assign stable numbers to remediation sources.

    The number is derived from the source identity instead of the order returned
    by ``os.walk``.  This keeps existing generated filenames stable when an
    unrelated remediation is added to the same path.  The base include file
    owns ``BASE_COUNTER``; remediation files use the remaining range.
    """
    used = {BASE_COUNTER}
    planned = []
    for source in sorted(sources, key=source_sort_key):
        identity = '\0'.join((
            path,
            severity or '',
            str(source.get('source_file', '')),
            str(source.get('role', '')),
            str(source.get('basename', '')),
        ))
        digest = hashlib.sha256(identity.encode('utf-8')).digest()
        number_range = MAX_REMEDIATION_COUNTER - FIRST_REMEDIATION_COUNTER + 1
        counter = FIRST_REMEDIATION_COUNTER + (
            int.from_bytes(digest[:4], 'big') % number_range
        )
        while counter in used:
            counter += 1
            if counter > MAX_REMEDIATION_COUNTER:
                counter = FIRST_REMEDIATION_COUNTER
        used.add(counter)
        planned.append((counter, source))
    return planned


def extract_meaningful_settings(lines: list[str]) -> list[str]:
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


def generate_base_yaml(
    path: str,
    role: str,
    config: dict[str, Any],
    out_dir: str,
    counter: int,
) -> str:
    """Generate a base MachineConfig that enables the .d include directory.

    Only paths whose MODULAR_PATHS entry sets ``needs_base`` get a base
    MC, and one is emitted per (path, role) so the include file reaches
    every role the drop-ins target.
    """
    shortname = safe_shortname(path)
    filename = f"{counter:02d}-{shortname}-base-{role}.yaml"
    name = f"{counter:02d}-{shortname}-base-{role}"

    include_path = os.path.join(config['include_dir'], config['base_file'])
    content = config['base_content']

    encoded_content = urllib.parse.quote(content + '\n', safe='')
    yaml_doc = {
        'apiVersion': 'machineconfiguration.openshift.io/v1',
        'kind': 'MachineConfig',
        'metadata': {
            'name': name,
            'labels': {
                ROLE_LABEL_KEY: role
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
        path: str,
        severity: str | None,
        remediation_info: dict[str, Any],
        config: dict[str, Any],
        out_dir: str,
        counter: int) -> str | None:
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

    # dropin_prefix: see MODULAR_PATHS. The counter is zero-padded to
    # the width of MAX_REMEDIATION_COUNTER so lexical order matches
    # remediation order, e.g. 10-0076-disable-x11.conf.
    prefix = config.get('dropin_prefix')
    if prefix:
        config_filename = (
            f"{prefix}-{counter:04d}-{desc}{config['file_extension']}")
    else:
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
                ROLE_LABEL_KEY: role
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


def write_combo_yaml(
    path: str,
    severity: str | None,
    sources: list[dict[str, Any]],
    out_dir: str,
) -> list[str]:
    """Write combined MachineConfig YAMLs (fallback for non-modular paths).

    One MC is emitted per role present in the sources so that, for
    example, master-targeted PAM remediations are not labelled worker.
    Line order is preserved because the merged files can be
    order-sensitive (PAM stacks, audit rules); alphabetical sorting
    would corrupt them.
    """
    outpaths = []
    shortname = safe_shortname(path)
    for role in sorted({source['role'] for source in sources}):
        role_sources = [s for s in sources if s['role'] == role]
        seen: set[str] = set()
        deduped_lines: list[str] = []
        for source in sorted(role_sources, key=source_sort_key):
            for line in source['lines']:
                if line not in seen:
                    seen.add(line)
                    deduped_lines.append(line)

        if severity:
            filename = f"{shortname}-{severity}-combo-{role}.yaml"
            name = f"75-{shortname}-{severity}-combo-{role}"
        else:
            filename = f"{shortname}-combo-{role}.yaml"
            name = f"75-{shortname}-combo-{role}"

        content = '\n'.join(deduped_lines) + '\n'
        encoded_content = urllib.parse.quote(content, safe='')

        yaml_doc = {
            'apiVersion': 'machineconfiguration.openshift.io/v1',
            'kind': 'MachineConfig',
            'metadata': {
                'name': name,
                'labels': {
                    ROLE_LABEL_KEY: role
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
            f.write(
                f"# Combined from {len(role_sources)} remediations "
                f"for {path}\n")
            if severity:
                f.write(f"# Severity: {severity}\n")
            yaml.dump(yaml_doc, f, default_flow_style=False, sort_keys=False)

        print(f"Created combo file: {outpath}")
        outpaths.append(outpath)
    return outpaths


def owning_config(target: str) -> dict[str, Any] | None:
    """Return the MODULAR_PATHS entry whose include_dir contains target."""
    for cfg in MODULAR_PATHS.values():
        if target.startswith(cfg['include_dir'] + '/'):
            return cfg
    return None


def validate_outputs(
        created_files: list[str],
        files_map: dict[tuple[str, str | None], list[dict[str, Any]]],
) -> tuple[list[str], list[str]]:
    """Check generated MachineConfigs before they replace prior output.

    Verifies that every file parses as a MachineConfig with the expected
    Ignition structure, that every target path is a known remediation
    path or lives under a modular include directory, that
    first-match-wins drop-ins carry no conflicting duplicate settings,
    and that every input group produced output. Returns
    (problems, warnings): problems block publication, warnings (e.g. an
    intentionally empty file such as /etc/securetty) do not.
    """
    problems: list[str] = []
    warnings: list[str] = []
    targets: list[str] = []
    # include_dir -> keyword -> occurrences of (value, drop-in name).
    # Drop-ins in the same directory are first-match-wins, so a keyword
    # set to two different values means the later value is silently
    # ignored. Keywords listed in a path's repeatable_keywords (e.g.
    # sshd's HostKey, where lines accumulate) are exempt.
    dropin_settings: dict[str, dict[str, list[tuple[str, str]]]] = {}
    repeatable_by_dir = {
        cfg['include_dir']: set(cfg.get('repeatable_keywords', ()))
        for cfg in MODULAR_PATHS.values()
    }
    combo_paths = {path for (path, _) in files_map}

    for filepath in created_files:
        basename = os.path.basename(filepath)
        try:
            with open(filepath) as f:
                doc = yaml.safe_load(f)
        except yaml.YAMLError as exc:
            problems.append(f"{basename}: invalid YAML: {exc}")
            continue
        if not isinstance(doc, dict):
            problems.append(f"{basename}: not a YAML mapping")
            continue
        # Guarded lookups: a key that is present but null must degrade
        # to a reported problem, not an AttributeError.
        metadata = doc.get('metadata') or {}
        config = (doc.get('spec') or {}).get('config') or {}
        name = metadata.get('name') or basename
        if doc.get('kind') != 'MachineConfig':
            problems.append(f"{name}: kind is not MachineConfig")
            continue
        if not (metadata.get('labels') or {}).get(ROLE_LABEL_KEY):
            problems.append(f"{name}: missing {ROLE_LABEL_KEY} label")
        ignition = (config.get('ignition') or {}).get('version')
        if ignition != IGNITION_VERSION:
            problems.append(
                f"{name}: ignition version {ignition!r}, "
                f"expected {IGNITION_VERSION!r}")
        entries = (config.get('storage') or {}).get('files')
        if not isinstance(entries, list) or not entries:
            problems.append(f"{name}: no storage.files entries")
            continue

        for entry in entries:
            target = entry.get('path') or ''
            targets.append(target)
            content = decode_data_source(
                (entry.get('contents') or {}).get('source'))
            if content is None:
                problems.append(f"{name}: {target}: source is not a data: URL")
                continue
            settings_lines = extract_meaningful_settings(content.splitlines())

            cfg = owning_config(target)
            # Base MCs legitimately contain only the Include directive,
            # and some files are intentionally empty (/etc/securetty,
            # .mco-keep placeholders), so emptiness is a warning.
            is_base = (cfg is not None
                       and os.path.basename(target) == cfg.get('base_file'))
            if not is_base and not settings_lines:
                warnings.append(
                    f"{name}: {target}: decoded settings are empty")
            if target not in combo_paths and cfg is None:
                problems.append(f"{name}: {target}: unsupported target path")
            if cfg is None:
                continue
            include_dir = cfg['include_dir']
            seen = dropin_settings.setdefault(include_dir, {})
            dropin = os.path.basename(target)
            for line in settings_lines:
                parts = line.split(None, 1)
                keyword = parts[0]
                if keyword in repeatable_by_dir[include_dir]:
                    continue
                value = parts[1] if len(parts) > 1 else ''
                seen.setdefault(keyword, []).append((value, dropin))

    for include_dir, keywords in dropin_settings.items():
        for keyword, occurrences in keywords.items():
            by_value: dict[str, list[str]] = {}
            for value, dropin in occurrences:
                by_value.setdefault(value, []).append(dropin)
            if len(by_value) <= 1:
                continue
            parts = []
            for value, dropins in by_value.items():
                where = (dropins[0] if len(dropins) == 1
                         else f"{len(dropins)} drop-ins")
                parts.append(f"{value!r} in {where}")
            problems.append(
                f"{include_dir}: {keyword} set to conflicting values: "
                f"{'; '.join(parts)} (first match wins; later values are "
                "ignored)")

    # Completeness: every (path, severity) group that reached generation
    # must have produced at least one file. A base include alone does
    # not cover a modular path — the group's drop-ins are the output.
    target_set = set(targets)
    dropin_dirs: set[str] = set()
    for target in target_set:
        cfg = owning_config(target)
        if cfg is not None and os.path.basename(target) != cfg.get('base_file'):
            dropin_dirs.add(cfg['include_dir'])
    for (path, severity), _sources in files_map.items():
        if path in MODULAR_PATHS:
            has_output = MODULAR_PATHS[path]['include_dir'] in dropin_dirs
        else:
            has_output = path in target_set
        if not has_output:
            problems.append(
                f"no output generated for {path} "
                f"(severity: {severity or 'all'})")

    return problems, warnings


def generate_outputs(
    files_map: dict[tuple[str, str | None], list[dict[str, Any]]],
    out_dir: str,
) -> list[str]:
    """Generate MachineConfig outputs for every (path, severity) group.

    Modular paths get one drop-in MC per remediation, plus a base MC per
    (path, role) for paths that need one; everything else falls back to
    per-role combo MCs.
    """
    created_files: list[str] = []
    emitted_bases: set[tuple[str, str]] = set()

    for (path, severity), sources in sorted(
            files_map.items(), key=group_sort_key):
        if path in MODULAR_PATHS:
            config = MODULAR_PATHS[path]
            print(f"\nProcessing modular path: {path} "
                  f"(severity: {severity or 'all'})")

            # Base MCs are per (path, role) and shared across severity
            # groups, so the include file lands on every role the
            # drop-ins target.
            if config.get('needs_base', False):
                for role in sorted({s['role'] for s in sources}):
                    if (path, role) in emitted_bases:
                        continue
                    base_file = generate_base_yaml(
                        path, role, config, out_dir, BASE_COUNTER)
                    created_files.append(base_file)
                    emitted_bases.add((path, role))

            for idx, source in stable_remediation_counters(
                    path, severity, sources):
                modular_file = generate_modular_yaml(
                    path, severity, source, config, out_dir, idx
                )
                if modular_file:
                    created_files.append(modular_file)
        else:
            sev = severity or 'all'
            print(f"\nProcessing non-modular path: {path} (severity: {sev})")
            combo_files = write_combo_yaml(path, severity, sources, out_dir)
            created_files.extend(combo_files)

    return created_files


def main() -> None:
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

    # Generate into a staging directory beside out_dir (same filesystem,
    # so publishing is a rename) and validate the complete set before
    # anything replaces prior output — a failed generation must not
    # leave a partial set behind.
    staging_dir = tempfile.mkdtemp(
        prefix='modular-staging-',
        dir=os.path.dirname(os.path.abspath(out_dir)))
    try:
        created_files = generate_outputs(files_map, staging_dir)
        problems, warnings = validate_outputs(created_files, files_map)
        for warning in warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        if problems:
            print(
                f"\nERROR: {len(problems)} validation problem(s); "
                f"{out_dir} was not modified:",
                file=sys.stderr)
            for problem in problems:
                print(f"  - {problem}", file=sys.stderr)
            sys.exit(2)

        # Publish: replace stale output only when there is new output to
        # take its place, so e.g. a severity filter that matches nothing
        # does not silently wipe previously generated files.
        if created_files:
            for stale in os.listdir(out_dir):
                if stale.endswith('.yaml'):
                    os.remove(os.path.join(out_dir, stale))
            for filepath in created_files:
                shutil.move(filepath, out_dir)
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)

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
