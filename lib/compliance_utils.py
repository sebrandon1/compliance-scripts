"""
Shared utility functions for compliance scripts.

Provides common functions used across multiple scripts to avoid
code duplication:
- safe_shortname: Convert file paths to safe shortnames for filenames
- parse_machineconfig_files: Parse MachineConfig YAMLs grouped by path/severity
- parse_severity_filter: Validate and parse severity filter strings
- check_virtualenv: Check for virtual environment and warn if missing
"""
from __future__ import annotations

import os
import re
import sys
import urllib.parse
from collections import defaultdict
from typing import Any

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.", file=sys.stderr)
    print("Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# Valid severity levels for compliance remediations
VALID_SEVERITIES = {"high", "medium", "low"}


def safe_shortname(path: str) -> str:
    """Convert a file path to a safe shortname for filenames.

    Handles numbered prefixes (e.g., 75-dac-modification.rules -> 75-dac-modification),
    file extensions, and special characters.
    """
    basename = os.path.basename(path)

    # Try to match optional numeric prefix and name with optional extension
    match = re.match(r'(\d+-)?(.+?)(?:\.[^.]+)?$', basename)
    if match:
        prefix = match.group(1) or ''
        name = match.group(2)
        return f"{prefix}{name}"

    # Fallback: clean up the basename
    name = re.sub(r'\.[^.]+$', '', basename)  # Remove extension
    name = re.sub(r'[^a-zA-Z0-9\-_]', '-', name)  # Replace special chars
    name = re.sub(r'-+', '-', name)  # Collapse multiple hyphens
    return name.strip('-')


def parse_machineconfig_files(
    src_dir: str,
    exclude_dirs: set[str] | None = None,
) -> tuple[
    dict[tuple[str, str | None], list[dict[str, Any]]],
    list[tuple[str, str]],
]:
    """Parse all MachineConfig YAMLs under src_dir (recursively) and group by
    (file path, severity), where severity is inferred from directory names
    containing one of: high, medium, low. If none found, severity is None.

    Args:
        src_dir: Source directory to scan for YAML files.
        exclude_dirs: Optional set of directory names to skip during traversal.

    Returns:
        (files_map, skipped) where:
        - files_map maps (path, severity) to list of dicts with keys:
          source_file, role, lines, basename
        - skipped is a list of (filepath, error) tuples for unparseable files.
    """
    files_map = defaultdict(list)
    skipped = []

    if exclude_dirs is None:
        exclude_dirs = set()

    for root, dirs, files in os.walk(src_dir):
        # Skip excluded directories
        dirs[:] = [d for d in dirs if d not in exclude_dirs]

        # Determine severity from the relative root path segments
        rel_root = os.path.relpath(root, src_dir)
        parts = [p.lower() for p in rel_root.split(os.sep) if p not in (".", "")]
        severity = None
        for p in parts:
            if p in VALID_SEVERITIES:
                severity = p
                break

        for fname in files:
            if not fname.endswith('.yaml'):
                continue
            fpath = os.path.join(root, fname)
            if not os.path.isfile(fpath):
                continue

            try:
                with open(fpath) as f:
                    docs = list(yaml.safe_load_all(f))
            except yaml.YAMLError as e:
                print(f"WARNING: Skipping {fpath}: YAML parse error: {e}",
                      file=sys.stderr)
                skipped.append((fpath, str(e)))
                continue

            for doc in docs:
                if not doc or doc.get('kind') != 'MachineConfig':
                    continue

                # Extract role from labels or default to worker
                role = doc.get('metadata', {}).get('labels', {}).get(
                    'machineconfiguration.openshift.io/role', 'worker'
                )

                file_entries = doc.get('spec', {}).get('config', {}).get(
                    'storage', {}).get('files', [])
                for file_entry in file_entries:
                    file_path = file_entry.get('path')
                    source = file_entry.get('contents', {}).get('source')
                    if file_path and source and source.startswith('data:,'):
                        decoded = urllib.parse.unquote(source[6:])
                        lines = [line for line in decoded.splitlines() if line.strip()]
                        files_map[(file_path, severity)].append({
                            'source_file': os.path.relpath(fpath, src_dir),
                            'role': role,
                            'lines': lines,
                            'basename': os.path.basename(fpath),
                        })

    return files_map, skipped


def parse_severity_filter(severity_str: str | None) -> set[str] | None:
    """Parse and validate a comma-separated severity filter string.

    Args:
        severity_str: Comma-separated string of severity levels
                      (e.g., "high,medium,low"). Case-insensitive.

    Returns:
        A set of validated severity strings, or None if input is None/empty.

    Raises:
        SystemExit: If any severity value is not in VALID_SEVERITIES.
    """
    if not severity_str:
        return None

    raw = severity_str.strip().lower().replace(' ', '')
    requested = [s for s in raw.split(',') if s]
    invalid = [s for s in requested if s not in VALID_SEVERITIES]
    if invalid:
        raise SystemExit(
            f"Invalid severity value(s): {','.join(invalid)}. "
            f"Allowed: {', '.join(sorted(VALID_SEVERITIES))}"
        )
    return set(requested)


def check_virtualenv() -> None:
    """Check if running in a virtual environment and warn if not."""
    in_venv = (
        hasattr(sys, 'real_prefix')
        or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix)
    )

    if not in_venv:
        print("Warning: Not running in a virtual environment!", file=sys.stderr)
        print("It's recommended to use a virtual environment to avoid dependency conflicts.", file=sys.stderr)
        print("\nTo set up a virtual environment:", file=sys.stderr)
        print("  python3 -m venv venv", file=sys.stderr)
        print("  source venv/bin/activate", file=sys.stderr)
        print("  pip install -r requirements.txt", file=sys.stderr)
        print("\nContinuing anyway...\n", file=sys.stderr)
